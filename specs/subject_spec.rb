require 'rubygems'
require 'rdf/threadsafe'
require 'json'

require File.dirname(__FILE__) + '/../openlibrary'

include OpenLibrary

def line_to_resource(line)
  (type,id,rev,date,data) = line.split("\t")
  elements = JSON.parse(data)
  resource = case type
  when "/type/author" then Author.new(elements)
  when "/type/edition" then Edition.new(elements)
  when "/type/work" then Work.new(elements)    
  when "/type/subject" then Subject.new(elements)
  end
  resource
end  

describe "OpenLibrary Subject" do  
  it "should correctly identify a Subject resource" do
    file = open(File.dirname(__FILE__) + "/data/subject_Word_formation.txt")
    while line = file.gets
      resource = line_to_resource(line)
      resource.should be_kind_of(Subject)
    end
  end
  
  it "should generate a URI based on the subject key" do
    file = open(File.dirname(__FILE__) + "/data/subject_Word_formation.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    subject_exists = false
    resource.statements.each {|stmt |
      if stmt.subject == RDF::URI.new(OpenLibrary::URI_PREFIX+"/subjects/Word_formation")        
        subject_exists = true
        break
      end
    }    
    subject_exists.should ==(true)
  end
  
  it "should generate a created statement" do
    file = open(File.dirname(__FILE__) + "/data/subject_Word_formation.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    created = nil   
    resource.statements.each do |stmt |
      next unless stmt.subject == RDF::URI.new(OpenLibrary::URI_PREFIX+"/subjects/Word_formation")     
      next unless stmt.predicate == RDF::DC.created
      created = stmt.object
    end
    created.should ==(RDF::Literal.new(DateTime.parse("2009-10-15T15:17:23.372937")))
  end
  it "should generate a modified statement" do
    file = open(File.dirname(__FILE__) + "/data/subject_Word_formation.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    mod = nil   
    resource.statements.each do |stmt |
      next unless stmt.subject == RDF::URI.new(OpenLibrary::URI_PREFIX+"/subjects/Word_formation")     
      next unless stmt.predicate == RDF::DC.modified
      mod = stmt.object
    end
    mod.should ==(RDF::Literal.new(DateTime.parse("2009-10-15T15:17:23.372937")))
  end  
end