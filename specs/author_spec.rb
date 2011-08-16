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

describe "OpenLibrary Author" do  
  it "should correctly identify an Author resource" do
    file = open(File.dirname(__FILE__) + "/data/author_OL1179559A.txt")
    while line = file.gets
      resource = line_to_resource(line)
      resource.should be_kind_of(Author)
    end
  end
  
  it "should generate a URI based on the author key" do
    file = open(File.dirname(__FILE__) + "/data/author_OL1179559A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    subject_exists = false
    resource.statements.each {|stmt |
      if stmt.subject == RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL1179559A")        
        subject_exists = true
        break
      end
    }    
    subject_exists.should ==(true)
  end
  
  it "should set the FOAF:name" do
    file = open(File.dirname(__FILE__) + "/data/author_OL1179559A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data  
    name_set = false
    resource.statements.each do |stmt|
      next unless stmt.subject == RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL1179559A")
      next unless stmt.predicate == RDF::FOAF.name
      next unless stmt.object.value == "August Dillmann"
      name_set = true
    end
    name_set.should ==(true)
  end
  
  it "should set the alternate forms of name" do    
    alt_names = ["Christian Friedrich August Dillmann", "Ch. F. A. Dillmann", "Friedrich August Dillmann", "F. A. Dillmann", "Augustus Dillmann", "August Dillmann", "A. Dillmann"]
    file = open(File.dirname(__FILE__) + "/data/author_OL1179559A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    resource.statements.each do |stmt|
      next unless stmt.subject == RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL1179559A")
      next unless stmt.predicate == RDF::SKOS.altLabel
      alt_names.delete(stmt.object.value)
    end    
    alt_names.should be_empty
  end
  
  it "should set the fuller form of name" do 
    file = open(File.dirname(__FILE__) + "/data/author_OL39937A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    name_set = false
    resource.statements.each do |stmt|    
      next unless stmt.subject == RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL39937A")   
      next unless stmt.predicate == RDF::RDAG2.fullerFormOfName
      next unless stmt.object.value == "Edward John Moreton Drax Plunkett"
      name_set = true
    end   
    name_set.should ==(true)
  end
  
  it "should store all of the names in the database and pipe delimited string" do
    file = open(File.dirname(__FILE__) + "/data/author_OL39937A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    DB.get("/authors/OL39937A").should eq(resource.name_strings.uniq.join("||"))    
  end
  
  it "should model the birth date" do
    file = open(File.dirname(__FILE__) + "/data/author_OL1179559A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    uri = RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL1179559A")
    graph = RDF::Graph.new
    resource.statements.each do |stmt|
      graph << stmt
    end

    birth = nil
    graph.query(:predicate=>RDF.type, :object=>RDF::BIO.Birth).each do |stmt|
      birth = stmt
    end
    birth.should_not be_nil    
    birth.subject.should be_kind_of(RDF::Node)
        
    birth_date = nil
    graph.query(:subject=>birth.subject, :predicate=>RDF::DC.date, :object=>"25 April 1823").each do |stmt|
      birth_date= stmt
    end
    birth_date.should_not be_nil

    event = nil
    graph.query(:subject=>uri, :predicate=>RDF::BIO.event, :object=>birth.subject).each do |stmt|
      event = stmt
    end
    event.should_not be_nil
    
    principal = nil
    graph.query(:subject=>birth.subject, :predicate=>RDF::BIO.principal, :object=>uri).each do |stmt|
      principal = stmt
    end
    principal.should_not be_nil
  end
    
  it "should model the deat date" do
    file = open(File.dirname(__FILE__) + "/data/author_OL1179559A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    uri = RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL1179559A")
    graph = RDF::Graph.new
    resource.statements.each do |stmt|
      graph << stmt
    end

    death = nil
    graph.query(:predicate=>RDF.type, :object=>RDF::BIO.Death).each do |stmt|
      death = stmt
    end
    death.should_not be_nil    
    death.subject.should be_kind_of(RDF::Node)
        
    death_date = nil
    graph.query(:subject=>death.subject, :predicate=>RDF::DC.date, :object=>"4 July 1894.").each do |stmt|
      death_date= stmt
    end
    death_date.should_not be_nil

    event = nil
    graph.query(:subject=>uri, :predicate=>RDF::BIO.event, :object=>death.subject).each do |stmt|
      event = stmt
    end
    event.should_not be_nil
    
    principal = nil
    graph.query(:subject=>death.subject, :predicate=>RDF::BIO.principal, :object=>uri).each do |stmt|
      principal = stmt
    end
    principal.should_not be_nil
  end    
  
  it "should model the website" do
    file = open(File.dirname(__FILE__) + "/data/author_OL1394244A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    uri = RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL1394244A") 
    website = RDF::URI.new("http://craphound.com/bio.php")
    website_match = false
    resource.statements.each do |stmt|   
      next unless stmt.subject == uri
      next unless stmt.predicate == RDF::FOAF.homepage
      next unless stmt.object == website
      website_match = true
    end
    website_match.should ==(true)
  end
  
  it "should model the bio" do
    file = open(File.dirname(__FILE__) + "/data/author_OL1394244A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    uri = RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL1394244A")
    bio = "From his website: Cory Doctorow (craphound.com) is a science fiction author, activist, journalist and blogger -- the co-editor of Boing Boing (boingboing.net) and the author of the bestselling Tor Teens/HarperCollins UK novel LITTLE BROTHER. He is the former European director of the Electronic Frontier Foundation and co-founded the UK Open Rights Group. Born in Toronto, Canada, he now lives in London.\r\n\r\n\r\n2 Creative Commons-licensed photos: cindiann: http://www.flickr.com/photos/trucolorsfly/2625294688/ & Joi Ito, Creative Commons Attribution 3.0."    
    bio_match = false
    resource.statements.each do |stmt|   
      next unless stmt.subject == uri
      next unless stmt.predicate == RDF::BIO.olb
      next unless stmt.object.value == bio
      bio_match = true
    end
    bio_match.should ==(true)    
  end
  
  it "should model the author's title" do
    file = open(File.dirname(__FILE__) + "/data/author_OL39937A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    title = false
    resource.statements.each do |stmt|    
      next unless stmt.subject == RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL39937A")   
      next unless stmt.predicate == RDF::RDAG2.titleOfThePerson
      next unless stmt.object.value == "18th Baron of Dunsany"
      title = true
    end   
    title.should ==(true)    
  end
  
  it "should model the author's wikipedia entry" do
    file = open(File.dirname(__FILE__) + "/data/author_OL1394244A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    uri = RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL1394244A")
    wiki = false
    db = false
    resource.statements.each do |stmt|    
      next unless stmt.subject == uri
      next unless stmt.predicate == RDF::FOAF.isPrimaryTopicOf || stmt.predicate == RDF::OWL.sameAs
      if stmt.predicate == RDF::FOAF.isPrimaryTopicOf && stmt.object =~ /wikipedia\.org/
        wiki = true
      end
      if stmt.predicate == RDF::OWL.sameAs && stmt.object =~ /dbpedia\.org/
        db = true
      end      
    end
    wiki.should ==(true)
    db.should ==(true)
  end
  
  it "should model the author's photos" do
    file = open(File.dirname(__FILE__) + "/data/author_OL1394244A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    uri = RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL1394244A")
    photos = []    
    resource.statements.each do |stmt|    
      next unless stmt.subject == uri
      next unless stmt.predicate == RDF::FOAF.depiction
      photos << stmt
    end    
    photos.length.should ==(6)
  end
  
  it "should model the author's links" do
    file = open(File.dirname(__FILE__) + "/data/author_OL1179559A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    uri = RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL1179559A")
    links = []
    resource.statements.each do |stmt|    
      next unless stmt.subject == uri
      next unless stmt.predicate == RDF::FOAF.page
      links << stmt.object.to_s
    end       
    links.should include("http://de.wikipedia.org/wiki/August_Dillmann") 
    links.should include("http://en.wikipedia.org/wiki/August_Dillmann")     
  end
  
  it "should write out any stored statements from DB about the author" do
    creations = ["http://openlibrary.org/books/OL3570141M","http://openlibrary.org/books/OL20957482M","http://openlibrary.org/works/OL5734718W"]
    DB.set("/authors/OL1394244A", creations.join("||"))
    DB.sadd "pending", "/authors/OL1394244A"
    file = open(File.dirname(__FILE__) + "/data/author_OL1394244A.txt")
    while line = file.gets
      resource = line_to_resource(line)
    end
    resource.parse_data
    uri = RDF::URI.new(OpenLibrary::URI_PREFIX+"/authors/OL1394244A")  
    resource.statements.each do |stmt|  
      next unless stmt.predicate == RDF::OL.author
      creations.delete(stmt.subject.to_s)
    end
    creations.should be_empty
    DB.sismember("pending", "/authors/OL1394244A").should ==(false)
  end
end