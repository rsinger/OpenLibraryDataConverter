require 'rubygems'
#require 'yajl'
require 'json'
require 'zlib'
#require 'rdf'
#require 'rdf/ntriples'
require '/Users/rossfsinger/Projects/rdf-threadsafe/lib/rdf/threadsafe'
require 'jruby_threach'
require 'redis'
require 'isbn/tools'
require './lib/author'
require './lib/edition'
require './lib/subject'
require './lib/work'

file = Zlib::GzipReader.open(ARGV[0])
i = 0
module RDF
  class BIBO < RDF::Vocabulary("http://purl.org/ontology/bibo/");end
  class RDA < RDF::Vocabulary("http://RDVocab.info/Elements/");end
  class RDAG2 < RDF::Vocabulary("http://RDVocab.info/ElementsGr2/");end
  class DCAM < RDF::Vocabulary("http://purl.org/dc/dcam/");end
  class FRBR < RDF::Vocabulary("http://purl.org/vocab/frbr/core#");end
  class BIO < RDF::Vocabulary("http://purl.org/vocab/bio/0.1/");end
  class OV < RDF::Vocabulary("http://open.vocab.org/terms/");end
  class OL < RDF::Vocabulary("http://api.talis.com/stores/openlibrary/terms#");end
end

module OpenLibrary
  def set_identifier
    @uri = RDF::URI.intern("#{URI_PREFIX}#{@data['key']}")
  end
  def add(s, p, o)
    @statements << RDF::Statement.new(s, p, o)
  end
end

include OpenLibrary

class Util
  def self.sanitize_url(str)
    return nil if str =~ /@/
    return nil if str !~ /([A-z0-9]*\.)+[A-z]/
    if str =~ /^http/ && str !~ /^http:\/\//
      str.sub!(/^http[^A-z0-9]*/,'http://')
    end
    if str !~ /^http:\/\//
      str = "http://#{str}"
    end
    str  
  end
  
  def self.load_lcsh(path)
    RDF::Reader.open(path) do | reader |
      reader.each_statement do |stmt|
        next unless stmt.predicate == RDF::SKOS.prefLabel || stmt.predicate == RDF::SKOS.altLabel
        next if stmt.object.to_s.match("/authorities/sj")
        DB.set stmt.object.value, stmt.subject.to_s
      end
    end    
  end
end

class String
  def slug
    slug = self.gsub(/[^A-z0-9\s\-]/,"")
    slug.gsub!(/\s/,"_")
    slug.downcase.strip_leading_and_trailing_punct
  end  
  def strip_trailing_punct
    self.sub(/[\.:,;\/\s]\s*$/,'').strip
  end
  def strip_leading_and_trailing_punct
    str = self.sub(/[\.:,;\/\s\)\]]\s*$/,'').strip
    return str.strip.sub(/^\s*[\.:,;\/\s\(\[]/,'')
  end  
  def lpad(count=1)
    "#{" " * count}#{self}"
  end
  
end

URI_PREFIX = "http://openlibrary.org"
DB = Redis.new

if ARGV[2]
  Util.load_lcsh(ARGV[2])
end

out = Zlib::GzipWriter.open("#{ARGV[1]}/openlibrary-#{DateTime.now.strftime("%Y-%m-%d")}.nt.gz")
queue = []
while line = file.gets
  (type,id,rev,date,data) = line.split("\t")
  elements = JSON.parse(data)
  resource = case type
  when "/type/author" then Author.new(elements)
  when "/type/edition" then Edition.new(elements)
  when "/type/work" then Work.new(elements)    
  when "/type/subject" then Subject.new(elements)
  end
  # if resource
  #   resource.parse_data
  #   resource.statements.each do |stmt|
  #     out << stmt.to_ntriples
  #   end
  # end
  queue << resource if resource
  if queue.length > 1000
    queue.threach(3) do |r|
      r.parse_data
    end
    queue.each do |r|
      r.statements.each do |stmt|
        out << stmt.to_ntriples
      end
    end
    queue = []
  end
  i += 1
  if i.to_s =~ /0000$/
    puts i
  end
end

# puts "Loading associations from DB"
# 
# i = 0
# puts "Loading author names"
# while authors = DB[:creations].select(:creations__olid.as(:book), :authors__names.as(:names)).filter{creations__id > i}.join(:authors, :olid => :author_olid).order(:creations__id).limit(100)
#   authors.each do |auth|
#     auth[:names].split("||").each do |name|
#       out << RDF::Statement.new(RDF::URI.intern("#{URI_PREFIX}#{auth[:book]}"), RDF::OL.author, name).to_ntriples
#     end
#   end
# end
# 
# puts "Loading subject uris"
# i = 0
# while subjects = DB[:book_subjects].select(:book_subjects__olid.as(:book), :subjects__uris.as(:subject)).filter{book_subjects__id > i}.join(:subjects, :subjects__label => :book_subjects__label).order(:book_subjects__id).limit(100)
#   subjects.each do |subject|
#     out << RDF::Statement.new(RDF::URI.intern("#{URI_PREFIX}#{subject[:book]}"), RDF::DC.subject, RDF::URI.intern(:subjec)).to_ntriples
#   end
# end

out.close

