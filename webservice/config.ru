
ENV['RACK_ENV'] ||= 'development'

require 'rubygems'
require 'bundler/setup'

# this will require all the gems not specified to a given group (default)
# and gems specified in your test group
Bundler.require(:default, ENV['RACK_ENV'].to_sym)

require File.dirname(__FILE__) + '/app'

run XbmApp

