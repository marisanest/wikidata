require 'csv'
require 'json'
require 'open-uri'
require 'uri'

CSV_FILE = 'result.csv'
CSV_RESULT_FILE = 'result2.csv'
API_URI = 'https://www.wikidata.org/w/api.php'

query = { # Query Parameter für wbgetentities
    action: 'wbgetentities',
    format: 'json'
}

def analyze_query_result(result, qids)
    if qids.length == 0
        [{}]
    elsif qids.length == 1
        label = result['entities'][qids[0]]['labels']['de'].nil? ? 'kein Label gefunden' : result['entities'][qids[0]]['labels']['de']['value']
        description = result['entities'][qids[0]]['descriptions']['de'].nil? ? 'keine Beschreibung gefunden' : result['entities'][qids[0]]['descriptions']['de']['value']
        day_of_birth = result['entities'][qids[0]]['claims']['P569'].nil? ? 'kein Geburtsdatum gefunden' : result['entities'][qids[0]]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time']
        occupation = result['entities'][qids[0]]['claims']['P106'].nil? ? 'kein Beruf gefunden' : result['entities'][qids[0]]['claims']['P106'][0]['mainsnak']['datavalue']['value']['id']

        [{qid: qids[0], label: label, description: description, day_of_birth: day_of_birth, occupation: occupation}]
    else
        qids.map{ |qid|
          label = result['entities'][qid]['labels']['de'].nil? ? 'kein Label gefunden' : result['entities'][qid]['labels']['de']['value']
          description = result['entities'][qid]['descriptions']['de'].nil? ? 'keine Beschreibung gefunden' : result['entities'][qid]['descriptions']['de']['value']
          day_of_birth = result['entities'][qid]['claims']['P569'].nil? ? 'kein Geburtsdatum gefunden' : result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time']
          occupation = result['entities'][qid]['claims']['P106'].nil? ? 'kein Beruf gefunden' : result['entities'][qid]['claims']['P106'][0]['mainsnak']['datavalue']['value']['id']
          {qid: qid, label: label, description: description, day_of_birth: day_of_birth, occupation: occupation}
        }
    end
end

def fill_row_with_results(row, results)

  qids = []
  labels = []
  description = []
  days_of_birth = []
  occupations = []

  results.each do |result|
    qids << result[0]
    labels << result[1]
    description << result[2]
    days_of_birth << result[3]
    occupations << result[4]
  end

  row[34] = qids.join ', ' #  row[34] ist die Wikidata QID
  row[35] = labels.join ', ' # row[35] ist das Wikidata Label
  row[36] = description.join ', '# row[36] ist die Wikidata Beschreibung
  row[37] = days_of_birth.join ', ' #  row[37] ist das Wikidata Geburtsdatum
  row[38] = occupations.join ', ' # row[38] ist der Wikidata Beruf

  row
end

puts "Start analysing CSV file..." # Logging

start_time = Time.now # Für das Logging: Zeit als Analyse gestartet ist
current_time = Time.now # Für das Logging: Aktuelle Zeit
rows = CSV.read(CSV_FILE, col_sep: ';').length # Für das Logging: Anzahl der Zeilen

CSV.open(CSV_RESULT_FILE, 'wb') do |csv|

  csv << HEADER # Header-Zeile wird in CSV-File geschrieben

  CSV.foreach(CSV_FILE, :headers => true, col_sep: ',') do |row|

    qids = row['QID']
    query[:ids] = qids
    query_result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(get_query)}").read) # API QID-Abfrage stellen und in JSON parsen
    results = analyze_get_query_result(query_result, qids) # Auswertung der API QID-Abfrage

    results = analyze_query_result(query_result, qids) # Auswertung der API QID-Abfrage
    csv << fill_row_with_results(row, results) # Zeile mit Ergebnissen werden dem Ergebnis-Array hinzugefügt

    sleep 0.5
    puts "Analysed row #{$.} form #{rows} rows in #{Time.now - current_time}s" # Logging
    current_time = Time.now # Aktuelle zeit wir aktualisiert
  end
end

puts "Analysed #{rows} rows in #{Time.now - start_time}s" # Logging
