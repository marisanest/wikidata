require 'csv'
require 'json'
require 'open-uri'
require 'uri'

CSV_FILE = 'data/data_for_information_retrival.csv'

CSV_RESULT_FILE = "results/information_retrival/qid_information_retrieval_result_#{Time.now.strftime('%Y%m%d')}.csv"

API_URI = 'https://www.wikidata.org/w/api.php'

HEADER = ['akad. Grad','Namenszusatz','Nachname','Vorname',
          'QID','Label','Beschreibung','Aliasse', 'T(G)','M(G)',
          'J(G)', 'Andere Geburtsdaten', 'Ort(G)','T(T)','M(T)','J(T)', 'Andere Todestage',
          'Ort(T)','Auszeichung','Beruf', 'Geschlecht', 'LCAuth', 'VIAF', 'GND', 'NTA-Nummer',
          'Munzinger Personen', 'ISNI', 'SUDOC-Normdaten', 'BnF-ID', 'FAST ID', 'weitere externe Ids']

KNOWN_EXTERNAL_ID_PROPERTIES = ['P244', 'P214', 'P227', 'P1006', 'P1284', 'P213', 'P269', 'P268', 'P2163']

def parse_query_result(query_result, qid)

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

    parse_result[:place_of_birth] = get_labels(qids).join ','

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

    parse_result[:place_of_death] = get_labels(qids).join ','

    # Awards Received
    qids = if query_result['entities'][qid]['claims']['P166'].nil? then
             []
           else
             query_result['entities'][qid]['claims']['P166'].map { |claim|
               claim['mainsnak']['datavalue']['value']['id']
             }
           end

    parse_result[:awards_received] = get_labels(qids).join ','

    # Occupations
    qids = if query_result['entities'][qid]['claims']['P106'].nil? then
             []
           else
             query_result['entities'][qid]['claims']['P106'].map { |claim|
               claim['mainsnak']['datavalue']['value']['id']
             }
           end

    parse_result[:occupations] = get_labels(qids).join ','

    # Sex
    parse_result[:sex] =  if query_result['entities'][qid]['claims']['P21'].nil? then
                   ''
                 else
                   query_result['entities'][qid]['claims']['P21'].map { |instance|
                     sex_qid = instance['mainsnak']['datavalue']['value']['id']
                      if sex_qid == 'Q6581097'
                        'männlich'
                      elsif sex_qid == 'Q6581072'
                        'weiblich'
                      elsif sex_qid == 'Q1097630'
                        'intersexuell'
                      elsif sex_qid == 'Q1052281'
                        'Transfrau'
                      elsif sex_qid == 'Q2449503'
                        'Transmann'
                      elsif sex_qid == 'Q48270'
                        'Genderqueer'
                      else
                        ''
                      end

                   }.join(',')
                 end

    # External Ids
    parse_result[:external_ids] = get_external_ids_as_hash(query_result, qid)

    parse_result
end

def get_external_ids_as_hash(query_result, qid)
  external_id_claims = query_result['entities'][qid]['claims'].values.flat_map { |claim|
    claim.reject { |value|
      value['mainsnak']['datatype'] != 'external-id'
    }
  }

  external_id_hash = {}

  external_id_claims.each { |claim|
    external_id_hash[claim['mainsnak']['property']] = [] unless external_id_hash.key?(claim['mainsnak']['property'])
    external_id_hash[claim['mainsnak']['property']] << { external_id: claim['mainsnak']['datavalue']['value'],
      label: get_label(claim['mainsnak']['property']),
      external_url: get_external_url(claim['mainsnak']['property'], claim['mainsnak']['datavalue']['value'])}
    }

    external_id_hash
end

def get_external_url(pid, id)
  result = wbgetentities(pid)
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
           ids: qids.is_a?(String) ? qids : qids.join('|')}

  JSON.parse(open("#{API_URI}?#{URI.encode_www_form(query)}").read)
end

def get_label(qid)
  result = wbgetentities(qid)

  if result['entities'][qid]['labels']['de'].nil?
    if result['entities'][qid]['labels']['en'].nil?
      qid
    else
      result['entities'][qid]['labels']['en']['value']
    end
  else
    result['entities'][qid]['labels']['de']['value']
  end
end

def get_labels(qids)
  result = wbgetentities(qids)

  qids.map{ |qid|
    if result['entities'][qid]['labels']['de'].nil?
      if result['entities'][qid]['labels']['en'].nil?
        qid
      else
        result['entities'][qid]['labels']['en']
      end
    else
      result['entities'][qid]['labels']['de']['value']
    end
  }
end

def fill_row_with_result(row, result)

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
    result_row << ''
  else
    date_of_births = result[:date_of_birth].split(', ')
    date_of_birth_first = date_of_births.first

    begin
      result_row << date_of_birth_first.strftime("%d")
      result_row << date_of_birth_first.strftime("%m")
      result_row << date_of_birth_first.strftime("%Y")
    rescue Exception
      tmp_date_of_birth = date_of_birth_first.gsub(/\+/, '').split('T')[0].split('-')
      if tmp_date_of_birth.length == 3
        result_row << tmp_date_of_birth[2]
        result_row << tmp_date_of_birth[1]
        result_row << tmp_date_of_birth[0]
      else
        result_row << "Error: #{date_of_birth_first}"
        result_row << ''
        result_row << ''
      end
    end

    if date_of_births.length > 1
      result_row << date_of_births.slice(1, (date_of_births.length - 1)).join(', ')
    else
      result_row << ''
    end
  end

  result_row << result[:place_of_birth]

  if result[:date_of_death] == ''
    result_row << ''
    result_row << ''
    result_row << ''
    result_row << ''
  else
    date_of_deaths = result[:date_of_death].split(', ')
    date_of_death_first = date_of_deaths.first

    begin
      result_row << date_of_death_first.strftime("%d")
      result_row << date_of_death_first.strftime("%m")
      result_row << date_of_death_first.strftime("%Y")
    rescue Exception
      tmp_date_of_death = date_of_death_first.gsub(/\+/, '').split('T')[0].split('-')
      if tmp_date_of_death.length == 3
        result_row << tmp_date_of_death[2]
        result_row << tmp_date_of_death[1]
        result_row << tmp_date_of_death[0]
      else
        result_row << "Error: #{date_of_death_first}"
        result_row << ''
        result_row << ''
      end
    end

    if date_of_deaths.length > 1
      result_row << date_of_deaths.slice(1, (date_of_deaths.length - 1)).join(', ')
    else
      result_row << ''
    end
  end

  result_row << result[:place_of_death]
  result_row << result[:awards_received]
  result_row << result[:occupations]
  result_row << result[:sex]
  KNOWN_EXTERNAL_ID_PROPERTIES.each { |property|
    result_row << (result[:external_ids].key?(property) ? result[:external_ids][property].map { |external_id|
      external_id_hash_as_string(external_id)
    }.join(' | ') : '')
  }
  result_row << result[:external_ids].keys.reject { |key|
    KNOWN_EXTERNAL_ID_PROPERTIES.include?(key)
  }.map { |key|
      result[:external_ids][key].map { |external_id|
        external_id_hash_as_string(external_id, true)
      }.join(' | ')
  }.join(' | ')

  result_row
end

def external_id_hash_as_string(external_id_hash, with_label=false)
  "#{with_label ? "#{external_id_hash[:label]}: " : ''}ID: #{external_id_hash[:external_id]} URL: #{external_id_hash[:external_url]}"
end

puts "Start analysing CSV file..." # Logging

start_time = Time.now # Für das Logging: Zeit als Analyse gestartet ist
current_time = Time.now # Für das Logging: Aktuelle Zeit
rows = CSV.read(CSV_FILE, col_sep: ',').length # Für das Logging: Anzahl der Zeilen

CSV.open(CSV_RESULT_FILE, 'wb', write_headers: true, headers: HEADER) do |csv|

  CSV.foreach(CSV_FILE, headers: true, col_sep: ',') do |row|

    qids = row['QID'].split(',')
    if qids.length == 1
      query_result = wbgetentities(qids[0]) # stellt API QID-Abfrage und parst es in JSON parsen
      parse_result = parse_query_result(query_result, qids[0]) # Auswertung der API QID-Abfrage
      csv << fill_row_with_result(row, parse_result) # Zeile mit Ergebnissen werden dem Ergebnis-Array hinzugefügt
    end

    sleep 0.5
    puts "Analysed row #{$.} form #{rows} rows in #{Time.now - current_time}s" # Logging
    current_time = Time.now # Aktuelle zeit wir aktualisiert
  end
end

puts "Analysed #{rows} rows in #{Time.now - start_time}s" # Logging
