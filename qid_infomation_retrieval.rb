require 'csv'
require 'json'
require 'open-uri'
require 'uri'

CSV_FILE = 'result.csv'
CSV_RESULT_FILE = 'result_comparison.csv'
API_URI = 'https://www.wikidata.org/w/api.php'
HEADER = ['akad. Grad','Namenszusatz','Nachname','Vorname', 'QID','Label','Beschreibung','Aliasse','T(G)','M(G)','J(G)','Geburtsdatum','Ort(G)','T(T)','M(T)','J(T)','Todestag','Ort(T)','Auszeichung','Beruf']

query = { # Query Parameter für wbgetentities
    action: 'wbgetentities',
    format: 'json'
}

def analyzeQueryResult(result, qid)
    res = {}
    query = {action: 'wbgetentities', format: 'json'}
    res[:qid] = qid
    res[:label] = result['entities'][qid]['labels']['de'].nil? ? result['entities'][qid]['labels']['en'].nil? ? '' : result['entities'][qid]['labels']['en']['value'] : result['entities'][qid]['labels']['de']['value']
    res[:description] = result['entities'][qid]['descriptions']['de'].nil? ? result['entities'][qid]['descriptions']['en'].nil? ? '' : result['entities'][qid]['descriptions']['en']['value'] : result['entities'][qid]['descriptions']['de']['value']
    res[:aliases] = result['entities'][qid]['aliases']['de'].nil? ? result['entities'][qid]['aliases']['en'].nil? ? '' : result['entities'][qid]['aliases']['en'].map{|instance| instance['value']}.join(',') : result['entities'][qid]['aliases']['de'].map{|instance| instance['value']}.join(',')
    begin
      res[:date_of_birth] = result['entities'][qid]['claims']['P569'].nil? ? '' : DateTime.iso8601(result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time'])
    rescue ArgumentError
      res[:date_of_birth] = result['entities'][qid]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time']
    end
    query[:ids] = result['entities'][qid]['claims']['P19'].nil? ? '' : result['entities'][qid]['claims']['P19'][0]['mainsnak']['datavalue']['value']['id']
    res[:place_of_birth] = getLabels(JSON.parse(open("#{API_URI}?#{URI.encode_www_form(query)}").read), query[:ids].split('|'))

    begin
      res[:date_of_death] = result['entities'][qid]['claims']['P570'].nil? ? '' : DateTime.iso8601(result['entities'][qid]['claims']['P570'][0]['mainsnak']['datavalue']['value']['time'])
    rescue ArgumentError
      res[:date_of_death] = result['entities'][qid]['claims']['P570'][0]['mainsnak']['datavalue']['value']['time']
    end
    query[:ids] = result['entities'][qid]['claims']['P20'].nil? ? '' : result['entities'][qid]['claims']['P20'][0]['mainsnak']['datavalue']['value']['id']
    res[:place_of_death] = getLabels(JSON.parse(open("#{API_URI}?#{URI.encode_www_form(query)}").read), query[:ids].split('|'))

    query[:ids] = result['entities'][qid]['claims']['P166'].nil? ? '' : result['entities'][qid]['claims']['P166'].map{|instance| instance['mainsnak']['datavalue']['value']['id']}.join('|')
    res[:awards_received] = getLabels(JSON.parse(open("#{API_URI}?#{URI.encode_www_form(query)}").read), query[:ids].split('|'))

    query[:ids] = result['entities'][qid]['claims']['P106'].nil? ? '' : result['entities'][qid]['claims']['P106'].map{|instance| instance['mainsnak']['datavalue']['value']['id']}.join('|')
    res[:occupations] = getLabels(JSON.parse(open("#{API_URI}?#{URI.encode_www_form(query)}").read), query[:ids].split('|'))
    res
end

def getLabels(data, qids)
  qids.map{ |qid|
      data['entities'][qid]['labels']['de'].nil? ? data['entities'][qid]['labels']['en'].nil? ? qid : data['entities'][qid]['labels']['en'].nil? : data['entities'][qid]['labels']['de']['value']
  }.join ','
end

def fillRowWithResult(row, result)

  result_row = []
  result_row << row['akad. Grad']
  result_row << row['Namenszusatz']
  result_row << row['Nachname']
  result_row << row['Vorname']

  result_row << result[:qid ]
  result_row << result[:label]
  result_row << result[:description]
  result_row << result[:aliases]

  begin
    result_row << result[:date_of_birth].strftime("%d")
    result_row << result[:date_of_birth].strftime("%m")
    result_row << result[:date_of_birth].strftime("%Y")
    result_row << ''
  rescue Exception
    result_row << ''
    result_row << ''
    result_row << ''
    result_row << result[:date_of_birth]
  end

  result_row << result[:place_of_birth]

  begin
    result_row << result[:date_of_death].strftime("%d")
    result_row << result[:date_of_death].strftime("%m")
    result_row << result[:date_of_death].strftime("%Y")
    result_row << ''
  rescue Exception
    result_row << ''
    result_row << ''
    result_row << ''
    result_row << result[:date_of_death]
  end

  result_row << result[:place_of_death]

  result_row << result[:awards_received]
  result_row << result[:occupations]

  result_row
end

puts "Start analysing CSV file..." # Logging

start_time = Time.now # Für das Logging: Zeit als Analyse gestartet ist
current_time = Time.now # Für das Logging: Aktuelle Zeit
rows = CSV.read(CSV_FILE, col_sep: ',').length # Für das Logging: Anzahl der Zeilen

CSV.open(CSV_RESULT_FILE, 'wb', write_headers: true, headers: HEADER) do |csv|

  CSV.foreach(CSV_FILE, headers: true, col_sep: ',') do |row|

    qids = row['QID'].split(',')
    if qids.length == 1
      query[:ids] = qids[0]
      query_result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(query)}").read) # API QID-Abfrage stellen und in JSON parsen
      result = analyzeQueryResult(query_result, query[:ids]) # Auswertung der API QID-Abfrage
      csv << fillRowWithResult(row, result) # Zeile mit Ergebnissen werden dem Ergebnis-Array hinzugefügt
    end

    sleep 0.5
    puts "Analysed row #{$.} form #{rows} rows in #{Time.now - current_time}s" # Logging
    current_time = Time.now # Aktuelle zeit wir aktualisiert
  end
end

puts "Analysed #{rows} rows in #{Time.now - start_time}s" # Logging
