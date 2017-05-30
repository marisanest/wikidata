require 'json'
require 'open-uri'
require 'uri'
require 'net/http'

CSV_FILE = 'result.csv'
CSV_RESULT_FILE = 'result2.csv'
API_URI = 'https://www.wikidata.org/w/api.php'

query = { # Query Parameter für wbgetentities
    action: 'wbgetentities',
    format: 'json'
}

query[:ids] = ['Q2157098']
query_result = JSON.parse(open("#{API_URI}?#{URI.encode_www_form(query)}").read)
#query_result.gsub!( / => /, ":" )
puts query_result['entities']['Q2157098']['sitelinks']['dewiki']['title']

name = query_result['entities']['Q2157098']['sitelinks']['dewiki']['title'].gsub!(/\s/, '_')

puts name

uri = "https://de.wikipedia.org/wiki/#{name}"

puts uri

res = Net::HTTP.get URI(uri)

puts res.include? 'Richter'
