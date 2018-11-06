require 'sinatra'

global = {}

set :port, 34567


get '/' do
  'lets ROCK!'
end
get '/frank-says' do
  'Put this in your pipe & smoke it!'
end