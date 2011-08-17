module OpenLibrary
  require 'cgi'
  require File.dirname(__FILE__) + '/lib/util'
  require File.dirname(__FILE__) + '/lib/author'
  require File.dirname(__FILE__) + '/lib/edition'
  require File.dirname(__FILE__) + '/lib/subject'
  require File.dirname(__FILE__) + '/lib/work'
  URI_PREFIX = "http://openlibrary.org"
  def set_identifier
    @uri = RDF::URI.new("#{URI_PREFIX}#{@data['key']}")
    @uri.normalize!
  end
  
  def uri
    return @uri
  end
  
  def add(s, p, o)
    @statements << RDF::Statement.new(s, p, o)
  end  
end