require 'csv'
require 'json'
require 'open-uri'
require 'uri'
require 'net/http'
require 'set'

CSV_FILE = 'data/data_for_qid_matching.csv'
CSV_RESULT_FILE = "results/qid_matching/qid_match_result_#{Time.now.strftime('%Y%m%d%H%M%S')}.csv"
API_URI = 'https://www.wikidata.org/w/api.php'
HEADER = ['akad. Grad','Namenszusatz','Nachname','Vorname','T','M','J','Ort','QID', 'indirekte QID']

search_query = { # Query Parameter für wbsearchentities
    action: 'wbsearchentities',
    language: 'de',
    format: 'json'
}

get_query = { # Query Parameter für wbgetentities
    action: 'wbgetentities',
    format: 'json'
}

def analyze_search_query_result(result)
    if result['search'].length == 0
      []
    elsif result['search'].length == 1
      [result['search'][0]['id']]
    else
      result['search'].map{ |res| res['id'] }
    end
end

def analyze_get_query_result(result, qids)
    qids.map{ |qid|
        res = {}
        res[:qid] = qid
        res[:labels] = {de: result['entities'][qid]['labels']['de'].nil? ? '' : result['entities'][qid]['labels']['de']['value'].downcase,
                        en: result['entities'][qid]['labels']['en'].nil? ? '' : result['entities'][qid]['labels']['en']['value'].downcase}
        res[:descriptions] = {de: result['entities'][qid]['descriptions']['de'].nil? ? '' : result['entities'][qid]['descriptions']['de']['value'].downcase,
                              en: result['entities'][qid]['descriptions']['en'].nil? ? '' : result['entities'][qid]['descriptions']['en']['value'].downcase}
        res[:day_of_birth] = result['entities'][qid]['claims']['P569'].nil? ? nil : {time: new_date_from_iso8601(result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time'], result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['precision']),
                                                                                     precision: result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['precision']}
        res[:occupations] = result['entities'][qid]['claims']['P106'].nil? ? nil : result['entities'][qid]['claims']['P106'].map{|occupation| occupation['mainsnak']['datavalue']['value']['id']}.join('|')
        res[:site_link] = result['entities'][qid]['sitelinks']['dewiki'].nil? ? nil : get_uri(result['entities'][qid]['sitelinks']['dewiki']['title'])
        res
    }
end

def is_right_page?(row, page)
  return false if is_wikimedia_disambiguation_page?(page)

  day_of_birth = (row['J'].nil? && row['M'].nil? && row['T'].nil?) ? nil
                  : {time: new_date(row['J'].to_i, row['M'].to_i, row['T'].to_i),
                    precision: precision(row['J'].to_i, row['M'].to_i, row['T'].to_i)}

  check = (is_right_label?(row, page[:labels][:de]) || is_right_label?(row, page[:labels][:en]))
  check = check && (page[:descriptions][:de].include?('richter') || page[:descriptions][:de].include?('jurist') || page[:descriptions][:en].include?('judge') || (page[:labels][:de].include?('richter') ? false : site_link_include_word?(page[:site_link], 'richter')))
  check = check && ((page[:day_of_birth].nil? || day_of_birth.nil?) ? true : do_dates_match?(page[:day_of_birth][:time], page[:day_of_birth][:precision], day_of_birth[:time], day_of_birth[:precision]))
  check = check && (page[:occupations].nil? ? true : (page[:occupations].include?('Q16533') || page[:occupations].include?('Q185351')))

  check
end

def new_date_from_iso8601(date, precision)
  if precision == 7
    DateTime.new(date.split('-')[0].sub('+', '').to_i - 100)
  elsif precision == 8 || precision == 9
    DateTime.new(date.split('-')[0].sub('+', '').to_i)
  elsif precision == 10
    DateTime.new(date.split('-')[0].sub('+', '').to_i, date.split('-')[1].to_i)
  elsif precision >= 11
    DateTime.iso8601(date)
  end
end

def new_date(year, month, day)
  if day == 0 && month == 0 && year == 0
      nil
  elsif day == 0 && month == 0
      DateTime.new(year)
  elsif day == 0
      DateTime.new(year, month)
  else
      DateTime.new(year, month, day)
  end
end

def precision(year, month, day)
  if day == 0 && month == 0 && year == 0
    -1
  elsif day == 0 && month == 0
    9
  elsif day == 0
    10
  else
    11
  end
end

def do_dates_match?(date1, precision1, date2, precision2)
  if precision1 < 7 || precision2 < 7
    false
  elsif precision1 == 7 || precision2 == 7
    date1.strftime('%C').eql?(date2.strftime('%C'))
  elsif precision1 == 8 || precision2 == 8
    (date1.year / 10).eql?((date2.year / 10))
  elsif precision1 == 9 || precision2 == 9
    date1.year.eql?(date2.year)
  elsif precision1 == 10 || precision2 == 10
    date1.year.eql?(date2.year) && date1.month.eql?(date2.month)
  elsif precision1 >= 11 || precision2 >= 11
    date1.year.eql?(date2.year) && date1.month.eql?(date2.month) && date1.day.eql?(date2.day)
  end
end

def is_wikimedia_disambiguation_page?(page)
  page[:descriptions][:de].include?('wikimedia-begriffsklärungsseite') || page[:descriptions][:en].include?('wikimedia disambiguation page')
end

def site_link_include_word?(site_link, word)
  return false if site_link.nil?
  begin
    html = Net::HTTP.get(URI(site_link))
  rescue URI::InvalidURIError
    puts "InvalidURIError for sitelink: #{site_link}!"
    return false
  end
  html.downcase.include?(word)
end

def is_right_label?(row, label)
  check = row['Vorname'].nil? ? false : " #{label} ".include?(" #{row['Vorname'].downcase} ")
  check && (row['Nachname'].nil? ? false : " #{label} ".include?(" #{row['Nachname'].downcase} "))
end

def get_matching_qids(row, pages)
    qids = {}
    qids[:matches] = []
    qids[:indirect_matches] = []

    pages.each do |page|
      qids[:matches] << page[:qid] if is_right_page?(row, page)
    end

    if qids[:matches].length == 0
      pages.each do |page|
        qids[:indirect_matches] << page[:qid] if ((is_right_label?(row, page[:labels][:de]) || is_right_label?(row, page[:labels][:en])) && !is_wikimedia_disambiguation_page?(page))
      end
    end
    qids
end

def get_uri(string)
  string.gsub!(/\s/, '_')
  string.gsub!(/ä/, '%E4')
  string.gsub!(/ü/, '%FC')
  string.gsub!(/ö/, '%F6')
  string.gsub!(/ß/, '%DF')
  string.gsub!(/Ä/, '%C4')
  string.gsub!(/Ü/, '%DC')
  string.gsub!(/Ö/, '%D6')
  return "https://de.wikipedia.org/wiki/#{string}"
end

puts "Start analysing CSV file..." # Logging

start_time = Time.now # Für das Logging: Zeit als Analyse gestartet ist
current_time = Time.now # Für das Logging: Aktuelle Zeit
rows = CSV.read(CSV_FILE, col_sep: ';').length # Für das Logging: Anzahl der Zeilen

CSV.open(CSV_RESULT_FILE, 'wb', write_headers: true, headers: HEADER) do |csv|

  CSV.foreach(CSV_FILE, headers: true, col_sep: ';') do |row|

    name = "#{row['Vorname']} #{row['Nachname']}"

    search_query[:search] = name # suche nach dem vollen Namen
    search_query_result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(search_query)}").read) # API Suchanfrage stellen und in JSON parsen
    qids = analyze_search_query_result(search_query_result) # Auswertung der API Suchanfrage

    name_with_affix = "#{row['Vorname']} #{row['Namenszusatz']} #{row['Nachname']}"

    search_query[:search] = name_with_affix # suche nach dem vollen Namen mit Namenszustaz
    search_query_result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(search_query)}").read) # API Suchanfrage stellen und in JSON parsen
    qids = qids + analyze_search_query_result(search_query_result) # Auswertung der API Suchanfrage

    qids = Set.new(qids).to_a

    get_query[:ids] = qids.join '|' # QID's die abgefragt werden
    get_query_result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(get_query)}").read) # API QID-Abfrage stellen und in JSON parsen

    results = analyze_get_query_result(get_query_result, qids) # Auswertung der API QID-Abfrage

    matching_qids = get_matching_qids(row, results)

    row['QID'] = matching_qids[:matches].join ', ' # direkt passende QID's werden Zeile hinzugefügt
    row['indirekte QID'] = matching_qids[:indirect_matches].join ', ' # indirekt passende QID's werden Zeile hinzugefügt
    csv << row # Zeile mit QID's werden dem Ergebnis-Array hinzugefügt

    sleep 0.5
    puts "Analysed row #{$.} form #{rows} rows in #{Time.now - current_time}s" # Logging
    current_time = Time.now # Aktuelle zeit wir aktualisiert
  end
end

puts "Analysed #{rows} rows in #{Time.now - start_time}s" # Logging
