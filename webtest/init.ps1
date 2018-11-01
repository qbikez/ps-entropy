install-module Require

ipmo Require
req PathUtils

choco install ruby -y
refresh-env

where-is ruby
ruby --version
where-is gem
gem --version

gem install bundler