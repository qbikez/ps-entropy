install-module Require

ipmo Require
req PathUtils

choco install ruby -y
refresh-env
gem install bundler