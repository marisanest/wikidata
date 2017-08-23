require 'csv'
require 'json'
require 'open-uri'
require 'uri'
require 'net/http'
require 'set'

# TODO mit und ohne namenszusatz suchen / unterscheidung gematchte QIDs und nicht eindeutig gematchte QIDS

CSV_FILE = 'namen.csv'
CSV_RESULT_FILE = "qid_match_result_#{Time.now.to_i.to_s}.csv"
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

def analyzeSearchQueryResult(result)
    if result['search'].length == 0
      []
    elsif result['search'].length == 1
      [result['search'][0]['id']]
    else
      result['search'].map{ |res| res['id'] }
    end
end

def analyzeGetQueryResult(result, qids)
    qids.map{ |qid|
        res = {}
        res[:qid] = qid
        res[:label] = result['entities'][qid]['labels']['de'].nil? ? 'kein Label gefunden' : result['entities'][qid]['labels']['de']['value']
        res[:de_description] = result['entities'][qid]['descriptions']['de'].nil? ? 'keine Beschreibung gefunden' : result['entities'][qid]['descriptions']['de']['value']
        res[:en_description] = result['entities'][qid]['descriptions']['en'].nil? ? 'keine Beschreibung gefunden' : result['entities'][qid]['descriptions']['en']['value']
        begin
          res[:day_of_birth] = result['entities'][qid]['claims']['P569'].nil? ? 'kein Geburtsdatum gefunden' : DateTime.iso8601(result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time'])
        rescue ArgumentError
          res[:day_of_birth] = result['entities'][qid]['claims']['P569'].nil? ? 'kein Geburtsdatum gefunden' : result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time']
          puts "DateTime ArgumentError for QID #{qid} with date #{result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time']}"
        end
        res[:occupation] = result['entities'][qid]['claims']['P106'].nil? ? 'kein Beruf gefunden' : result['entities'][qid]['claims']['P106'][0]['mainsnak']['datavalue']['value']['id']
        res[:site_link] = result['entities'][qid]['sitelinks']['dewiki'].nil? ? nil : getURI(result['entities'][qid]['sitelinks']['dewiki']['title'])
        res
    }
end

def isRightPerson(row, person)

    vorname = row['Vorname'].nil? ? '' : row['Vorname']
    nachname = row['Nachname'].nil? ? '' : row['Nachname']

    begin
      day_of_birth = DateTime.new(row['J'].to_i, row['M'].to_i, row['T'].to_i)
    rescue ArgumentError
      day_of_birth = -1
      puts "DateTime ArgumentError for #{vorname} #{nachname} with date #{row['J'].to_i} #{row['M'].to_i} #{row['T'].to_i}"
    end

    check = ((person[:label].include?(vorname) && person[:label].include?(nachname)) && (person[:de_description].downcase.include?('richter') || person[:en_description].downcase.include?('judge') || person[:day_of_birth].eql?(day_of_birth) || person[:occupation].eql?('Q16533')))

    if check == false && !vorname.downcase.include?('richter') && !nachname.downcase.include?('richter')
      begin
        wikipedia = person[:site_link].nil? ? '' : Net::HTTP.get(URI(person[:site_link]))
      rescue URI::InvalidURIError
        puts "InvalidURIError for #{vorname} #{nachname} with sitelink: #{person[:site_link]}!"
        wikipedia = ''
      end
      check = wikipedia.downcase.include?('richter') && person[:label].include?(vorname) && person[:label].include?(nachname)
    end
    check
end

def getMatchingQids(row, persons)
    qids = {}
    qids[:matches] = []
    qids[:indirect_matches] = []

    persons.each do |person|
      qids[:matches] << person[:qid] if isRightPerson(row, person)
    end

    if qids[:matches].length == 0
      persons.each do |person|
        qids[:indirect_matches] << person[:qid]
      end
    end
    qids
end

def getURI(string)
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
    qids = analyzeSearchQueryResult(search_query_result) # Auswertung der API Suchanfrage

    name_with_affix = "#{row['Vorname']} #{row['Namenszusatz']} #{row['Nachname']}"

    search_query[:search] = name_with_affix # suche nach dem vollen Namen mit Namenszustaz
    search_query_result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(search_query)}").read) # API Suchanfrage stellen und in JSON parsen
    qids = qids + analyzeSearchQueryResult(search_query_result) # Auswertung der API Suchanfrage

    qids = Set.new(qids).to_a

    get_query[:ids] = qids.join '|' # QID's die abgefragt werden
    get_query_result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(get_query)}").read) # API QID-Abfrage stellen und in JSON parsen

    results = analyzeGetQueryResult(get_query_result, qids) # Auswertung der API QID-Abfrage

    matching_qids = getMatchingQids(row, results)

    row['QID'] = matching_qids[:matches].join ', ' # direkt passende QID's werden Zeile hinzugefügt
    row['indirekte QID'] = matching_qids[:indirect_matches].join ', ' # indirekt passende QID's werden Zeile hinzugefügt
    csv << row # Zeile mit QID's werden dem Ergebnis-Array hinzugefügt

    sleep 0.5
    puts "Analysed row #{$.} form #{rows} rows in #{Time.now - current_time}s" # Logging
    current_time = Time.now # Aktuelle zeit wir aktualisiert
  end
end

puts "Analysed #{rows} rows in #{Time.now - start_time}s" # Logging
