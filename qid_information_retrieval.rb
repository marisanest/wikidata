require 'csv'
require 'json'
require 'open-uri'
require 'uri'

CSV_FILE = 'qid_match_result.csv'

CSV_RESULT_FILE = "qid_information_retrieval_result_#{Time.now.to_i.to_s}.csv"

API_URI = 'https://www.wikidata.org/w/api.php'

HEADER = ['akad. Grad','Namenszusatz','Nachname','Vorname',
          'QID','Label','Beschreibung','Aliasse', 'T(G)','M(G)',
          'J(G)','Geburtsdatum','Ort(G)','T(T)','M(T)','J(T)',
          'Todestag','Ort(T)','Auszeichung','Beruf', 'Geschlecht', 'Identifikatoren']

# Query Parameter für wbgetentities
query = {
    action: 'wbgetentities',
    format: 'json'
}

def parseQueryResult(query_result, qid)

    parse_result = {}

    parse_result[:qid] = qid

    # Labels
    parse_result[:label] = if query_result['entities'][qid]['labels']['de'].nil? then
                    if query_result['entities'][qid]['labels']['en'].nil? then
                      ''
                    else
                      query_result['entities'][qid]['labels']['en']['value']
                    end
                  else
                    query_result['entities'][qid]['labels']['de']['value']
                  end

    # Description
    parse_result[:description] = if query_result['entities'][qid]['descriptions']['de'].nil? then
                          if query_result['entities'][qid]['descriptions']['en'].nil? then
                            ''
                          else
                            query_result['entities'][qid]['descriptions']['en']['value']
                          end
                        else
                          query_result['entities'][qid]['descriptions']['de']['value']
                        end

    # Aliases
    parse_result[:aliases] = if query_result['entities'][qid]['aliases']['de'].nil? then
                      if query_result['entities'][qid]['aliases']['en'].nil? then
                        ''
                      else
                          query_result['entities'][qid]['aliases']['en'].map { |instance|
                            instance['value']
                          }.join(', ')
                      end
                    else
                      query_result['entities'][qid]['aliases']['de'].map { |instance|
                        instance['value']
                      }.join(', ')
                    end

    # Date of Birth

    parse_result[:date_of_birth] = if query_result['entities'][qid]['claims']['P569'].nil? then
                            ''
                          else
                            query_result['entities'][qid]['claims']['P569'].map { |claim|
                              begin
                                DateTime.iso8601(claim['mainsnak']['datavalue']['value']['time'])
                              rescue ArgumentError
                                claim['mainsnak']['datavalue']['value']['time']
                              end
                            }.join(', ')
                          end


    # Place of Birth
    qids = if query_result['entities'][qid]['claims']['P19'].nil? then
            []
          else
            query_result['entities'][qid]['claims']['P19'].map { |claim|
              claim['mainsnak']['datavalue']['value']['id']
            }
          end

    parse_result[:place_of_birth] = getLabels(qids)

    # Date of Death
    parse_result[:date_of_death] = if query_result['entities'][qid]['claims']['P570'].nil? then
                            ''
                          else
                            query_result['entities'][qid]['claims']['P570'].map { |claim|
                              begin
                                DateTime.iso8601(claim['mainsnak']['datavalue']['value']['time'])
                              rescue ArgumentError
                                claim['mainsnak']['datavalue']['value']['time']
                              end
                              }.join(', ')
                            end

    # Place of Death
    qids = if query_result['entities'][qid]['claims']['P20'].nil? then
             []
           else
             query_result['entities'][qid]['claims']['P20'].map { |claim|
               claim['mainsnak']['datavalue']['value']['id']
             }
           end

    parse_result[:place_of_death] = getLabels(qids)

    # Awards Received
    qids = if query_result['entities'][qid]['claims']['P166'].nil? then
             []
           else
             query_result['entities'][qid]['claims']['P166'].map { |claim|
               claim['mainsnak']['datavalue']['value']['id']
             }
           end

    parse_result[:awards_received] = getLabels(qids)

    # Occupations
    qids = if query_result['entities'][qid]['claims']['P106'].nil? then
             []
           else
             query_result['entities'][qid]['claims']['P106'].map { |claim|
               claim['mainsnak']['datavalue']['value']['id']
             }
           end

    parse_result[:occupations] = getLabels(qids)

    # Sex
    parse_result[:sex] =  if query_result['entities'][qid]['claims']['P21'].nil? then
                   ''
                 else
                   query_result['entities'][qid]['claims']['P21'].map { |instance|
                     property = instance['mainsnak']['property']
                      if property == 'Q6581097'
                        'männlich'
                      elsif property == 'Q6581072'
                        'weiblich'
                      elsif property == 'Q1097630'
                        'intersexuell'
                      elsif property == 'Q1052281'
                        'Transfrau'
                      elsif property == 'Q2449503'
                        'Transmann'
                      elsif property == 'Q48270'
                        'Genderqueer'
                      else
                        ''
                      end

                   }.join(',')
                 end

    # External Ids
    parse_result[:external_ids] = getExternalIds(query_result, qid)

    parse_result
end

def getExternalIds(query_result, qid)
  external_ids = query_result['entities'][qid]['claims'].values.reject { |claim|
    claim.map { |value|
      value['mainsnak']['datatype'] == 'external-id'
    }.include?(false)
  }

  external_ids.map { |claim|
    claim.map { |value|
      property_id = value['mainsnak']['property']
      external_id = value['mainsnak']['datavalue']['value']
      label = getLabels([property_id])
      external_url = getExternalURL(property_id, external_id)
      "#{label}: ID: #{external_id} URL: #{external_url}"
    }.join(', ')
  }.join(', ')
end

def getExternalURL(pid, id)
  result = wbgetentities([pid])
  formatter_URLs = result['entities'][pid]['claims']['P1630']
  if formatter_URLs.nil?
    ''
  else
    formatter_URLs.map { |formatter_URL|
      formatter_URL['mainsnak']['datavalue']['value'].gsub!(/\$1/, id)
    }.join(', ')
  end
end

def wbgetentities(qids)
  query = {action: 'wbgetentities',
           format: 'json',
           ids: qids.join('|')}

  JSON.parse(open("#{API_URI}?#{URI.encode_www_form(query)}").read)
end

def getLabels(qids)
  result = wbgetentities(qids)

  qids.map{ |qid|
    if result['entities'][qid]['labels']['de'].nil? then
      if result['entities'][qid]['labels']['en'].nil? then
        qid
      else
        result['entities'][qid]['labels']['en'].nil?
      end
    else
      result['entities'][qid]['labels']['de']['value']
    end
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

  if result[:date_of_birth] == ''
    result_row << ''
    result_row << ''
    result_row << ''
    result_row << result[:date_of_birth]
  else
    begin
      result_row << result[:date_of_birth].strftime("%d")
      result_row << result[:date_of_birth].strftime("%m")
      result_row << result[:date_of_birth].strftime("%Y")
      result_row << ''
    rescue Exception
      tmp_date_of_birth = result[:date_of_birth].gsub(/\+/, '').split('T')[0].split('-')
      if tmp_date_of_birth.length == 3
        result_row << tmp_date_of_birth[2]
        result_row << tmp_date_of_birth[1]
        result_row << tmp_date_of_birth[0]
        result_row << result[:date_of_birth]
      else
        result_row << ''
        result_row << ''
        result_row << ''
        result_row << result[:date_of_birth]
      end
    end
  end

  result_row << result[:place_of_birth]

  if result[:date_of_death] == ''
    result_row << ''
    result_row << ''
    result_row << ''
    result_row << result[:date_of_death]
  else
    begin
      result_row << result[:date_of_death].strftime("%d")
      result_row << result[:date_of_death].strftime("%m")
      result_row << result[:date_of_death].strftime("%Y")
      result_row << ''
    rescue Exception
      tmp_date_of_death = result[:date_of_death].gsub(/\+/, '').split('T')[0].split('-')
      if tmp_date_of_death.length == 3
        result_row << tmp_date_of_death[2]
        result_row << tmp_date_of_death[1]
        result_row << tmp_date_of_death[0]
        result_row << result[:date_of_death]
      else
        result_row << ''
        result_row << ''
        result_row << ''
        result_row << result[:date_of_death]
      end
    end
  end


  result_row << result[:place_of_death]

  result_row << result[:awards_received]
  result_row << result[:occupations]
  result_row << result[:sex]
  result_row << result[:external_ids]

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
      query_result = wbgetentities([qids[0]]) # stellt API QID-Abfrage und parst es in JSON parsen
      parse_result = parseQueryResult(query_result, qids[0]) # Auswertung der API QID-Abfrage
      csv << fillRowWithResult(row, parse_result) # Zeile mit Ergebnissen werden dem Ergebnis-Array hinzugefügt
    end

    sleep 0.5
    puts "Analysed row #{$.} form #{rows} rows in #{Time.now - current_time}s" # Logging
    current_time = Time.now # Aktuelle zeit wir aktualisiert
  end
end

puts "Analysed #{rows} rows in #{Time.now - start_time}s" # Logging
