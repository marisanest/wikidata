require 'csv'
require 'json'
require 'open-uri'
require 'uri'
require 'net/http'

CSV_FILE = 'namen.csv'
CSV_RESULT_FILE = 'result.csv'
API_URI = 'https://www.wikidata.org/w/api.php'
HEADER = ['akad. Grad','Namenszusatz','Nachname','Vorname','T','M','J','Ort','QID']

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
    if qids.length == 0
        [[]]
    elsif qids.length == 1
        label = result['entities'][qids[0]]['labels']['de'].nil? ? 'kein Label gefunden' : result['entities'][qids[0]]['labels']['de']['value']
        description = result['entities'][qids[0]]['descriptions']['de'].nil? ? 'keine Beschreibung gefunden' : result['entities'][qids[0]]['descriptions']['de']['value']
        begin
          day_of_birth = result['entities'][qids[0]]['claims']['P569'].nil? ? 'kein Geburtsdatum gefunden' : DateTime.iso8601(result['entities'][qids[0]]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time'])
        rescue ArgumentError
          day_of_birth = result['entities'][qids[0]]['claims']['P569'].nil? ? 'kein Geburtsdatum gefunden' : result['entities'][qids[0]]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time']
          puts "DateTime ArgumentError for QID #{qids[0]} with date #{result['entities'][qids[0]]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time']}"
        end
        occupation = result['entities'][qids[0]]['claims']['P106'].nil? ? 'kein Beruf gefunden' : result['entities'][qids[0]]['claims']['P106'][0]['mainsnak']['datavalue']['value']['id']
        site_link = result['entities'][qids[0]]['sitelinks']['dewiki'].nil? ? nil : "https://de.wikipedia.org/wiki/#{result['entities'][qids[0]]['sitelinks']['dewiki']['title'].gsub!(/\s/, '_')}"
        [[qids[0], label, description, day_of_birth, occupation, site_link]]
    else
        qids.map{ |qid|
          label = result['entities'][qid]['labels']['de'].nil? ? 'kein Label gefunden' : result['entities'][qid]['labels']['de']['value']
          description = result['entities'][qid]['descriptions']['de'].nil? ? 'keine Beschreibung gefunden' : result['entities'][qid]['descriptions']['de']['value']
          begin
            day_of_birth = result['entities'][qid]['claims']['P569'].nil? ? 'kein Geburtsdatum gefunden' : DateTime.iso8601(result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time'])
          rescue ArgumentError
            day_of_birth = result['entities'][qid]['claims']['P569'].nil? ? 'kein Geburtsdatum gefunden' : result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time']
            puts "DateTime ArgumentError for QID #{qid} with date #{result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time']}"
          end
          occupation = result['entities'][qid]['claims']['P106'].nil? ? 'kein Beruf gefunden' : result['entities'][qid]['claims']['P106'][0]['mainsnak']['datavalue']['value']['id']
          site_link = result['entities'][qid]['sitelinks']['dewiki'].nil? ? nil : "https://de.wikipedia.org/wiki/#{result['entities'][qid]['sitelinks']['dewiki']['title'].gsub!(/\s/, '_')}"
          [qid, label, description, day_of_birth, occupation, site_link]
        }
    end
end

def isRightPerson(row, data)

  name = "#{row['Vorname']} #{row['Nachname']}"

  begin
    day_of_birth = DateTime.new(row['J'].to_i, row['M'].to_i, row['T'].to_i)
  rescue ArgumentError
    day_of_birth = -1
    puts "DateTime ArgumentError for #{name} with date #{row[8].to_i} #{row[7].to_i} #{row[6].to_i}"
  end

  if name.eql? data[1]
    bool = (data[2].downcase.include?('richter') || data[3].eql?(day_of_birth) || data[4].eql?('Q16533')) ? true : false
    if bool == false
      begin
        res = data[5].nil? ? '' : Net::HTTP.get(URI(data[5]))
      rescue URI::InvalidURIError
        puts "InvalidURIError for #{name} with sitelink: #{data[5]}!"
        res = ''
      end
      res.include?('Richter')
    else
      true
    end
  else
    false
  end
end

def get_matching_qids(row, data)
  qids = []
  data.each do |d|
    qids << d[0] if isRightPerson(row, d)
  end
  qids
end

puts "Start analysing CSV file..." # Logging

start_time = Time.now # Für das Logging: Zeit als Analyse gestartet ist
current_time = Time.now # Für das Logging: Aktuelle Zeit
rows = CSV.read(CSV_FILE, col_sep: ';').length # Für das Logging: Anzahl der Zeilen

CSV.open(CSV_RESULT_FILE, 'wb') do |csv|

  csv << HEADER # Header-Zeile wird in CSV-File geschrieben

  CSV.foreach(CSV_FILE, :headers => true, col_sep: ';') do |row|
    name = "#{row['Vorname']} #{row['Nachname']}" # row[5] ist der Vorname, row[4] der Nachname

    search_query[:search] = name # suche nach dem vollen Namen
    search_query_result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(search_query)}").read) # API Suchanfrage stellen und in JSON parsen
    qids = analyze_search_query_result(search_query_result) # Auswertung der API Suchanfrage

    get_query[:ids] = qids.join '|' # QID's die abgefragt werden
    get_query_result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(get_query)}").read) # API QID-Abfrage stellen und in JSON parsen
    results = analyze_get_query_result(get_query_result, qids) # Auswertung der API QID-Abfrage

    matching_qids = get_matching_qids(row, results)

    row['QID'] = matching_qids.join ', ' # QID's werden Zeile hinzugefügt
    csv << row # Zeile mit QID's werden dem Ergebnis-Array hinzugefügt

    sleep 0.5
    puts "Analysed row #{$.} form #{rows} rows in #{Time.now - current_time}s" # Logging
    current_time = Time.now # Aktuelle zeit wir aktualisiert
  end
end

puts "Analysed #{rows} rows in #{Time.now - start_time}s" # Logging

# Resultat ohne Wikipedia Sitelinks: 329
