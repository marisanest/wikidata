require 'csv'
require 'json'
require 'open-uri'
require 'uri'

CSV_FILE = 'Sample.csv'
API_URI = 'https://www.wikidata.org/w/api.php'

def analyze_result(result)
    if result['search'].length == 0
        []
    elsif result['search'].length == 1
        [result['search'][0]['id']]
    else
        result['search'].map{ |res| res['id'] }
    end
end

def analyze_get_result(result, qids)
    if qids.length == 0
        'kein Item gefunden'
    elsif qids.length == 1
        if result['entities'][qids[0]]['claims']['P569'].nil?
          [qids[0], 'kein Geburtsdatum gefunden'].join ': '
        else
          [qids[0], result['entities'][qids[0]]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time']].join ': '
        end
    else
        result['entities'].map{ |res|
          if res[1]['claims']['P569'].nil?
            [res[0], 'kein Geburtsdatum gefunden'].join ': '
          else
            [res[0], res[1]['claims']['P569'][0]['mainsnak']['datavalue']['value']['time']].join ': '
          end
        }.join ', '
    end
end

search_query = {
    action: 'wbsearchentities',
    language: 'de',
    format: 'json'
}

get_query = {
    action: 'wbgetentities',
    format: 'json'
}

CSV.foreach(CSV_FILE, col_sep: ',') do |row|
    name = "#{row[5]} #{row[4]}" # row[5] ist der Vorname, row[4] der Nachname
    search_query[:search] = name # suche nach dem vollen Namen

    result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(search_query)}").read) # API Anfrage stellen und auswerten
    qids = analyze_result(result)

    #puts "#{name}: #{qids}"

    get_query[:ids] = qids.join '|'
    get_result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(get_query)}").read)
    puts "#{name}: #{analyze_get_result(get_result, qids)}"

    sleep 0.5
end

# Ergebnisse:
# Martin Heidenhain: Q1904004, Q1904005, Q75087
# Richard Karl Selowsky: nicht gefunden
# Alexander von Normann: nicht gefunden
# Richard Busch: Q57199
# Karl Heck: Q1731452, Q18711850, Q20737351, Q27055450, Q1273375, Q1731453, Q1731454
# Werner Hülle: Q1401170, Q2807299, Q1650707, Q1564942
# Werner Wolfhart: nicht gefunden
# Fritz Lindenmaier: Q1467352
# Werner Birnbach: nicht gefunden
# Helmuth Delbrück: Q1604397
