require 'rubygems'
require 'rdf/threadsafe'
require 'json'
require 'redis'
require 'isbn/tools'
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
        elsif stmt.object.is_a?(RDF::URI)
          next
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

describe "OpenLibrary Edition" do  
  it "should correctly identify Edition resource" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002396M.txt")    
    resource.parse_data
    resource.should be_kind_of(Edition)    
  end
  
  it "should generate a URI based on the edition key" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002396M.txt")    
    resource.parse_data
    subject_exists = false
    resource.statements.each {|stmt |
      if stmt.subject == RDF::URI.new(OpenLibrary::URI_PREFIX+"/books/OL1002396M")        
        subject_exists = true
        break
      end
    }    
    subject_exists.should ==(true)
  end
  
  it "should model the edition's title" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002411M.txt")
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::RDA.titleProper, :object=>"Biochemistry"}]).should be_true
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.title, :object=>"Biochemistry; Mosby's USMLE step 1 reviews"}]).should be_true    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::RDA.otherTitleInformation, :object=>"Mosby's USMLE step 1 reviews"}]).should be_true    
  end
  
  it "should model the edition's variant titles" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002411M.txt")
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::RDA.variantTitle, :object=>"Mosby's USMLE step 1 reviews--biochemistry"}]).should be_true        
  end  
  
  it "should model the edition's publishers" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002396M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC11.publisher, :object=>"Millbrook Press"}]).should be_true    
  end
  it "should model the edition's copyright date" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL20343282M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.dateCopyrighted, :object=>"1972, 1978"}]).should be_true    
  end 
  
  it "should model the edition's contributors" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL20343282M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC11.contributor, :object=>"Greenwood, Joy."}]).should be_true    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC11.contributor, :object=>"Ramblers' Association. Lake District Area."}]).should be_true        
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC11.creator, :object=>"Joy Greenwood"}]).should be_true     
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL10292211M.txt")    
    resource.parse_data       
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC11.contributor, :object=>"Anthony Hogg"}]).should be_true
  end
  
  it "should model the edition's pagination" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL20343282M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.extent, :object=>"64p. :"}]).should be_true    
  end 
  
  it "should model the edition's physical dimensions" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL10023172M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::RDA.dimensions, :object=>"11.8 x 8 x 0.2 inches"}]).should be_true    
  end   
  
  it "should model the edition's places of publication" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002411M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::RDA.placeOfPublication, :object=>"St. Louis"}]).should be_true    
  end  
  
  it "should model the edition's record source" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL100043M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC11.source, :object=>"marc:marc_records_scriblio_net/part28.dat:62741961:1376"}]).should be_true    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC11.source, :object=>"marc:marc_loc_updates/v36.i33.records.utf8:3020091:1375"}]).should be_true        
  end  
  
  it "should model the edition's number of pages" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL100043M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.numPages, :object=>"103"}]).should be_true            
  end  
  
  it "should model the edition's publish date" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002396M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.issued, :object=>"1997"}]).should be_true            
  end  
  
  it "should model the edition's edition name" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002024M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.edition, :object=>"1st ed."}]).should be_true            
  end  
  
  it "should model the edition's work title" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1009515M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::RDA.titleOfTheWork, :object=>"Sciences de la vie dans la pense\314\201e franc\314\247aise de XVIIIe sie\314\200cle."}]).should be_true            
  end 
  
  it "should model the edition's by statement" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002396M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::RDA.statementOfResponsibility, :object=>"Andrew Matthews ; illustrated by Sheila Moxley."}]).should be_true            
  end  
  
  it "should model the edition's language" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002396M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.language, :object=>RDF::URI.new("http://purl.org/NET/marccodes/languages/eng#lang")}]).should be_true            
  end  
  
  it "should model the edition's ISBNs" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002024M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn10, :object=>"0060275278"}]).should be_true
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn, :object=>"0060275278"}]).should be_true  
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn13, :object=>"9780060275273"}]).should be_true
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn, :object=>"9780060275273"}]).should be_true
      
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn10, :object=>"0064420477"}]).should be_true
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn, :object=>"0064420477"}]).should be_true  
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn13, :object=>"9780064420471"}]).should be_true
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn, :object=>"9780064420471"}]).should be_true        
    
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL24919867M.txt")    
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn10, :object=>"8862742614"}]).should be_true
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn, :object=>"8862742614"}]).should be_true  
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn13, :object=>"9788862742610"}]).should be_true
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.isbn, :object=>"9788862742610"}]).should be_true    
  end
  
  it "should model the edition's urls" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1009515M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::FOAF.page, :object=>RDF::URI.new("http://www.h-net.org/review/hrev-a0a9k8-aa")}]).should be_true            
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::FOAF.page, :object=>RDF::URI.new("http://www.loc.gov/catdir/description/cam028/96049548.html")}]).should be_true            
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::FOAF.page, :object=>RDF::URI.new("http://www.loc.gov/catdir/toc/cam027/96049548.html")}]).should be_true                    
  end  
  
  it "should model the edition's uris" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1009515M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::URI.intern("http://purl.org/ontology/bibo/uri"), :object=>RDF::URI.new("http://www.h-net.org/review/hrev-a0a9k8-aa")}]).should be_true            
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::URI.intern("http://purl.org/ontology/bibo/uri"), :object=>RDF::URI.new("http://www.loc.gov/catdir/description/cam028/96049548.html")}]).should be_true            
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::URI.intern("http://purl.org/ontology/bibo/uri"), :object=>RDF::URI.new("http://www.loc.gov/catdir/toc/cam027/96049548.html")}]).should be_true                    
  end  
  
  it "should model the edition's LC classification number" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1009515M.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.subject, :object=>RDF::URI.intern("http://api.talis.com/stores/openlibrary/items/lcc/QH305+.R5413+1997#class")}]).should be_true
  end  
  
  it "should model the edition's genres" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002024M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.type, :object=>"Juvenile fiction"}]).should be_true            
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.type, :object=>"Fiction"}]).should be_true            
  end
  
  it "should model the edition's table of contents" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL19374587M.txt")    
    resource.parse_data
    toc = "1. Outside and Inside History\n2. The Sense of the Past\n3. What Can History Tell Us about Contemporary Society?\n4. Looking Forward: History and the Future\n5. Has History Made Progress?\n6. From Social History to the History of Society\n7. Historians and Economists: I\n8. Historians and Economists: II\n9. Partisanship\n10. What Do Historians Owe to Karl Marx?\n11. Marx and History\n12. All Peoples Have a History\n13. British History and the Annales: A Note\n14. On the Revival of Narrative\n15. Postmodernism in the Forest\n16. On History from Below\n17. The Curious History of Europe\n18. The Present as History\n19. Can We Write the History of the Russian Revolution?\n20. Barbarism: A Userb2ss Guide\n21. Identity History Is Not Enough."
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.tableOfContents, :object=>toc}]).should be_true            
  end  
  
  it "should model the edition's LCCN" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1009515M.txt")    
    resource.parse_data
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.lccn, :object=>"96049548"}]).should be_true                      
  end  
  
  it "should model the edition's authors" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL20587107M.txt")
    resource.parse_data
    authors = [RDF::URI.intern("http://openlibrary.org/authors/OL6075577A"), RDF::URI.intern("http://openlibrary.org/authors/OL6075578A")]  
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.creator, :object=>authors.first}]).should be_true
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.creator, :object=>authors.last}]).should be_true  
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.authorList}]).should be_true  
    DB["/authors/OL6075577A"].should include(resource.uri.to_s)
    DB["/authors/OL6075578A"].should include(resource.uri.to_s)  
    
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
  
  it "should model the editions's description" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002396M.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.description, :object=>"A collection of creation stories from various world cultures, both ancient and contemporary."}]).should be_true
  end  
  
  it "should model the edition's Dewey number" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002396M.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.subject, :object=>RDF::URI.intern("http://api.talis.com/stores/openlibrary/items/ddc/291.1%2F3#class")}]).should be_true    
  end  
  
  it "should model the edition's country of publication" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002396M.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::RDA.placeOfPublication, :object=>RDF::URI.intern("http://purl.org/NET/marccodes/countries/ctu#location")}]).should be_true    
  end
  
  it "should model the edition's identifiers" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002396M.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::FOAF.isPrimaryTopicOf, :object=>RDF::URI.intern("http://www.librarything.com/work/1536693")}]).should be_true    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::FOAF.isPrimaryTopicOf, :object=>RDF::URI.intern("http://www.goodreads.com/book/show/1780787")}]).should be_true        
  end  
  
  it "should model the edition's OCLC numbers" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002396M.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.oclcnum, :object=>"35586866"}]).should be_true    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::FOAF.isPrimaryTopicOf, :object=>RDF::URI.intern("http://worldcat.org/oclc/35586866")}]).should be_true    
    
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL18904767M.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::BIBO.oclcnum, :object=>"12101731"}]).should be_true    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::FOAF.isPrimaryTopicOf, :object=>RDF::URI.intern("http://worldcat.org/oclc/12101731")}]).should be_true    
  end
  
  it "should model the edition's subjects" do
    uris = [RDF::URI.new("http://id.loc.gov/authorities/subjects/sh99005711"), RDF::URI.new("http://id.loc.gov/authorities/subjects/sh99005576"),
       RDF::URI.new("http://id.loc.gov/authorities/names/n79021783")]
    DB.set("Homes and haunts", uris[0].to_s)
    DB.set("Criticism and interpretation", uris[1].to_s)
    DB.set("Italy", uris[2].to_s)

    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL24919867M.txt")
    resource.parse_data    
    subjects = ["Congresses", "Homes and haunts", "Criticism and interpretation", "Edmondo De Amicis (1846-1908)", "Italy", "Turin"]

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
  
  it "should model the edition's ocaid" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL20587107M.txt")
    resource.parse_data    

    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC11.identifier, :object=>"dieproblemeeine00ottogoog"}]).should be_true    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::FOAF.page, :object=>RDF::URI.intern("http://www.archive.org/details/dieproblemeeine00ottogoog")}]).should be_true        
  end  
  
  it "should model the edition's notes" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1009515M.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::RDA.note, :object=>"Includes bibliographical references (p. [691]-734) and index."}]).should be_true    
  end  
  
  it "should model the edition's work" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL19374587M.txt")
    resource.parse_data    
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::DC.isVersionOf, :object=>RDF::URI.new("http://openlibrary.org/works/OL495651W")}]).should be_true  
    match_triples(resource.statements, [{:subject=>RDF::URI.new("http://openlibrary.org/works/OL495651W"), :predicate=>RDF::DC.hasVersion, :object=>resource.uri}])  
    match_triples(resource.statements, [{:subject=>resource.uri, :predicate=>RDF::OV.commonManifestation, :object=>RDF::URI.new("http://openlibrary.org/works/OL495651W")}]).should be_true  
    match_triples(resource.statements, [{:subject=>RDF::URI.new("http://openlibrary.org/works/OL495651W"), :predicate=>RDF::OV.commonManifestation, :object=>resource.uri}])    
  end  
  
  it "should model the edition's book cover" do
    resource = resource_from_file(File.dirname(__FILE__) + "/data/edition_OL1002024M.txt")
    resource.parse_data  
    covers = []    
    resource.statements.each do |stmt|    
      next unless stmt.subject == resource.uri
      next unless stmt.predicate == RDF::FOAF.depiction
      covers << stmt.object
    end    
    covers.length.should ==(6)    
    covers.should include(RDF::URI.new("http://covers.openlibrary.org/b/id/3857941-S.jpg"))    
    covers.should include(RDF::URI.new("http://covers.openlibrary.org/b/id/3857863-L.jpg"))        
  end  
end