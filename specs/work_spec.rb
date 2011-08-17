require 'rubygems'
require 'rdf/threadsafe'
require 'json'
require 'redis'
require File.dirname(__FILE__) + '/../openlibrary'
DB = Redis.new
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

def resource_from_file(file_path)
  resource = nil
  file = open(file_path)
  while line = file.gets
    resource = line_to_resource(line)  
  end
  resource
end

def match_triples(statements, queries)
  remaining = queries.length
  queries.each do |query|
    statements.each do |stmt|
      next if query[:subject] && query[:subject] != stmt.subject
      next if query[:predicate] && query[:predicate] != stmt.predicate
      if query[:object]
        if query[:object].is_a?(RDF::URI)
          next unless query[:object] == stmt.object
        else
          next unless query[:object] == stmt.object.value
        end
      end
      remaining -= 1
    end
  end
  case remaining
  when 0 then true
  else false
  end
end

describe "OpenLibrary Work" do  
  it "should correctly identify Work resource" do
    file = open(File.dirname(__FILE__) + "/data/work_OL11928803W.txt")
    while line = file.gets
      resource = line_to_resource(line)
      resource.should be_kind_of(Work)
    end
  end
  
  it "should generate a URI based on the work key" do
    file = open(File.dirname(__FILE__) + "/data/work_OL11928803W.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    subject_exists = false
    resource.statements.each {|stmt |
      if stmt.subject == RDF::URI.new(OpenLibrary::URI_PREFIX+"/works/OL11928803W")        
        subject_exists = true
        break
      end
    }    
    subject_exists.should ==(true)
  end
  
  it "should model the work's title" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/work_OL1005131W.txt")
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::RDA.titleProper, :object=>"Os pobres da cidade"}]).should be_true
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.title, :object=>"Os pobres da cidade; vida e trabalho, 1880-1920"}]).should be_true    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::RDA.otherTitleInformation, :object=>"vida e trabalho, 1880-1920"}]).should be_true    
  end
  
  it "should model the first published date" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/work_OL11928803W.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.created, :object=>"2004"}]).should be_true
  end
  
  it "should model the work's authors" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/work_OL11928803W.txt")
    resource.parse_data
    authors = [RDF::URI.intern("http://openlibrary.org/authors/OL352128A"), RDF::URI.intern("http://openlibrary.org/authors/OL6893618A")]  
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.creator, :object=>authors.first}]).should be_true
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.creator, :object=>authors.last}]).should be_true  
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.authorList}]).should be_true  
    DB["/authors/OL352128A"].should include(resource.uri.to_s)
    DB["/authors/OL6893618A"].should include(resource.uri.to_s)  
    
    graph = RDF::Graph.new
    auth_list = nil
    resource.statements.each do |stmt|
      graph << stmt
      if stmt.predicate == RDF::BIBO.authorList
        auth_list = stmt.object
      end
    end
    auth_list.should be_kind_of(RDF::Node)
    
    while stmts = graph.query(:subject=>auth_list)
      stmts.each do |stmt|
        if stmt.predicate == RDF.first
          @authors.first.should ==(stmt.object)
          @authors.delete(stmt.object)
        elsif stmt.predicate == RDF.rest
          auth_list = stmt.predicate
          break if auth_list == RDF.nil
        end
      end      
    end
    @authors.should be_empty
  end
end