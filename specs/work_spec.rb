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

def follow_list(graph, subject)
  stmts = []
  rest = nil
  graph.query(:subject=>subject).each do |stmt|
    stmts << stmt
    if stmt.predicate == RDF.rest
      rest = stmt.object
    end
  end
  {:statements=>stmts, :next=>rest}
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
    resource = resource_from_file(File.dirname(__FILE__) + "/data/work_OL2506185W.txt")
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
    while list = follow_list(graph, auth_list)
      list[:statements].each do |stmt|
        if stmt.predicate == RDF.first
          authors.first.should ==(stmt.object)
          authors.delete(stmt.object)
        end        
      end
      break if list[:next] == RDF.nil
      auth_list = list[:next]
    end

    authors.should be_empty
  end
  
  it "should model the work's subjects" do
    uris = [RDF::URI.new("http://id.loc.gov/authorities/subjects/sh85124233"), RDF::URI.new("http://id.loc.gov/authorities/subjects/sh85026255"),
       RDF::URI.new("http://id.loc.gov/authorities/subjects/sh85061212"), RDF::URI.new("http://id.loc.gov/authorities/subjects/sh2001008850"),
       RDF::URI.new("http://id.loc.gov/authorities/names/n79007233"), RDF::URI.new("http://id.loc.gov/authorities/names/n80001244")]
    DB.set("Sociology, Urban", uris[0].to_s)
    DB.set("City and town life", uris[1].to_s)
    DB.set("History", uris[2].to_s)
    DB.set("Social conditions", uris[3].to_s)
    DB.set("Canada", uris[4].to_s)
    DB.set("Québec (Province)", uris[5].to_s)

    resource = resource_from_file(File.dirname(__FILE__) + "/data/work_OL11928803W.txt")
    resource.parse_data    
    subjects = ["City and town life", "History", "Social conditions", "Sociology, Urban", "Urban Sociology", "To 1763", "To 1763 (New France)", "Canada", "Québec (Province)"]

    resource.statements.each do |stmt|
      next unless stmt.subject == resource.uri
      next unless stmt.predicate == RDF::DC11.subject
      subjects.should include(stmt.object.value)
      subjects.delete(stmt.object.value)
    end
    subjects.should be_empty    
    resource.statements.each do |stmt|
      next unless stmt.subject == resource.uri
      next unless stmt.predicate == RDF::DC.subject
      next if stmt.object =~ /stores\/openlibrary\/items\// # skip LCC and DDC for now
      uris.should include(stmt.object)
      uris.delete(stmt.object)
    end    
    uris.should be_empty
  end
  
  it "should model the work's description" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/work_OL100126W.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.description, :object=>"After Cuno Masseys business partner is murdered by a gang of outlaws, he takes to the trail to find the killers. But Cunos mission of vengeance becomes a rescue mission when he learns that the outlaws have kidnapped a young Chinese woman"}]).should be_true
  end
  
  it "should model the work's LC classification number" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/work_OL2506185W.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.subject, :object=>RDF::URI.intern("http://api.talis.com/stores/openlibrary/items/lcc/LB1131+.B4#class")}]).should be_true
  end
  
  it "should model the work's Dewey number" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/work_OL2506185W.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.subject, :object=>RDF::URI.intern("http://api.talis.com/stores/openlibrary/items/ddc/155.4%2F13#class")}]).should be_true    
  end
  
  it "should model the work's book cover" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/work_OL2506185W.txt")
    resource.parse_data  
    covers = []    
    resource.statements.each do |stmt|    
      next unless stmt.subject == resource.uri
      next unless stmt.predicate == RDF::FOAF.depiction
      covers << stmt.object
    end    
    covers.length.should ==(3)    
    covers.should include(RDF::URI.new("http://covers.openlibrary.org/w/id/5614028-S.jpg"))    
  end
end