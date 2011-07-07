require 'rdf'
require 'rdf/ntriples'
require 'rdf/ntriples/format'
require 'rdf/ntriples/writer'
require 'rdf/ntriples/reader'
require 'zlib'
require 'rufus/tokyo/tyrant'

DB = Rufus::Tokyo::Tyrant.new("127.0.0.1", 1978)

module RDF
  class OL < RDF::Vocabulary("http://api.talis.com/stores/openlibrary/terms#");end
end

augment_file = Zlib::GzipWriter.open("#{ARGV[1]}/openlibrary-augment-#{DateTime.now.strftime("%Y-%m-%d")}.nt.gz") 
input_file = File.new(ARGV[0], 'r')
file = Zlib::GzipReader.new(input_file)

def new_triple_from_creator(stmt)
  stmts = []  
  if author = stmt.object.to_s.sub("http://openlibrary.org","")
    author.split("||").each do |auth|
      stmts << RDF::Statement.new(stmt.subject, RDF::OL.author, auth)
    end
  end
  stmts
end

def new_triple_from_subject(stmt)
  if subject_uri = DB[stmt.object.value]
    return [RDF::Statement.new(stmt.subject, RDF::DC.subject, RDF::URI.intern(subject_uri))]
  end
  []
end

while line = file.gets
  next unless line =~ /\<http\:\/\/purl\.org\/dc\/terms\/creator\>/ or line =~ /\<http\:\/\/purl\.org\/dc\/elements\/1\.1\/subject\/>/
  RDF::NTriples::Reader.open(ARGV[2]) do | reader |
    reader.each_statement do |stmt|
      augments = case stmt.predicate
      when RDF::DC.creator then new_triple_from_creator(stmt)
      when RDF::DC11.subject then new_triple_from_subject(stmt)
      end
      augments.each do |augment|
        augment_file << augment.to_ntriples if augment
      end
    end
  end
end
file.close
augment_file.close