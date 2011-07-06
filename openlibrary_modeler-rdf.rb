require 'rubygems'
require 'jruby/path_helper'
require 'rdf/threadsafe'
require 'rdf'
require 'rdf/ntriples'
require 'rdf/ntriples/format'
require 'rdf/ntriples/writer'
require 'rdf/ntriples/reader'
require 'jruby_threach'
require 'isbn/tools'
require 'zlib'
require 'json'

numthreads = 3

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


input_file = File.new(ARGV[0], 'r')
file = Zlib::GzipReader.new(input_file)

i = 0
module RDF
  class BIBO < RDF::Vocabulary("http://purl.org/ontology/bibo/");end
  class RDA < RDF::Vocabulary("http://RDVocab.info/Elements/");end
  class RDAG2 < RDF::Vocabulary("http://RDVocab.info/ElementsGr2/");end
  class DCAM < RDF::Vocabulary("http://purl.org/dc/dcam/");end
  class FRBR < RDF::Vocabulary("http://purl.org/vocab/frbr/core#");end
  class BIO < RDF::Vocabulary("http://purl.org/vocab/bio/0.1/");end
  class OV < RDF::Vocabulary("http://open.vocab.org/terms/");end
end



URI_PREFIX = "http://openlibrary.org"


class Tripler
  attr_reader :file_prefix, :file_number, :file, :graph, :bad_graph
  attr_accessor :lines
  def initialize
    #@file_prefix = prefix
    @file_number = 0
    #@graph = RDF::Graph.new
    @graph = []
    #new_file
    @i = 0
    @j = 0
    @lines = []
  end

  def gen_author_list(authors)
    rest = RDF.nil
    authors.reverse.each do | au |
      n = RDF::Node.new
      @graph << [n,RDF.first,au]
      @graph << [n,RDF.rest,rest]
      rest = n
    end
    rest
  end

  def sanitize_url(str)
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

  def add_author_to_graph(data)
    resource = RDF::URI.new(URI_PREFIX+data['key'])
    @graph << [resource, RDF.type, RDF::FOAF.Agent]

    if data['personal_name'] && !data['personal_name'].empty?
      @graph << [resource, RDF::FOAF.name, data['personal_name']]

      if data['name'] && !data['name'].empty?
        @graph << [resource, RDF::SKOS.altLabel, data['name']]
      end
    elsif data['name'] && !data['name'].empty?
      @graph << [resource, RDF::FOAF.name, data['name']]
    end
    if data['birth_date'] && !data['birth_date'].empty?
      node = RDF::Node.new
      @graph << [node, RDF.type, RDF::BIO.Birth]
      @graph << [node, RDF::BIO.principal, resource]
      @graph << [resource, RDF::BIO.event, node]
      @graph << [node, RDF::DC.date, data['birth_date']]
    end
    if data['death_date'] && !data['death_date'].empty?
      node = RDF::Node.new
      @graph << [node, RDF.type, RDF::BIO.Death]
      @graph << [node, RDF::BIO.principal, resource]
      @graph << [resource, RDF::BIO.event, node]
      @graph << [node, RDF::DC.date, data['death_date']]
    end  
    if data['website'] && !data['website'].empty?
      if url = sanitize_url(data['website'])
        begin
          hp = RDF::URI.new(url)
          hp.normalize!
          u = URI.parse(hp.to_s)
          @graph << [resource, RDF::FOAF.homepage, hp]
        rescue
        end
      end
    end
    if data['bio'] && !data['bio'].empty?
      if data['bio'].is_a?(String)
        @graph << [resource, RDF::BIO.olb, data['bio']]
      elsif data['bio'].is_a?(Hash) && data['bio']['value'] && !data['bio']['value'].empty?
        @graph << [resource, RDF::BIO.olb,data['bio']['value']]
      end
    end
  
    if data['title'] && !data['title'].empty?
      @graph << [resource, RDF::RDAG2.titleOfThePerson, data['title']]
    end
  
    if data['alternate_names'] && !data['alternate_names'].empty?
      [*data['alternate_names']].each do |alt_name|
        next if alt_name.nil? or alt_name.empty?
        @graph << [resource, RDF::DC.alternative, alt_name]
      end
    end
    if data['wikipedia'] && !data['wikipedia'].empty?
      [*data['wikipedia']].each do |wik|
        next if wik.nil? or wik.empty?
        next unless w = sanitize_url(wik)
        begin
          wp = RDF::URI.new(w)
          wp.normalize!
          u = URI.parse(wp.to_s)
          @graph << [resource, RDF::FOAF.page, wp]
          if wp.host =~ /wikipedia\.org/
            dbpedia = RDF::URI.new(wp.to_s)
            dbpedia.host = "dbpedia.org"
            dbpedia.path.sub!(/\/wiki\//,"/resource/")
            @graph << [resource, RDF::OWL.sameAs, dbpedia]
          end
        rescue
        end
      end
    end
    if data['fuller_name'] && !data['fuller_name'].empty?
      [*data['fuller_name']].each do |fn|
        next if fn.nil? or fn.empty?
        @graph << [resource, RDF::RDAG2.fullerFormOfName, fn]
      end
    end
    
    if data['photos'] && !data['photos'].empty?
      [*data['photos']].each do |photo|
        next if photo.nil?
        ["S","M","L"].each do |size|
          @graph << [resource, RDF::FOAF.depiction, RDF::URI.new("http://covers.openlibrary.org/a/id/#{photo}-#{size}.jpg")]
        end
      end
    end
    
    if data['links'] && !data['links'].empty?
      if data['links'].is_a?(Array)
        data['links'].each do |link|
          if link.is_a?(Hash)
            if link['url']
              @graph << [resource, RDF::FOAF.page, link['url']]
            end
          end
        end
      end
    end
  end  

  def add_edition_to_graph(data)
    resource = RDF::URI.new(URI_PREFIX+data['key'])
    @graph << [resource, RDF.type, RDF::BIBO.Book]
    if data['languages']
      data['languages'].each do |lang|
        if lang['key']
          lang_str = lang['key']
          lang_str.sub!(/^\/languages\//,'')
          lang_str.sub!(/^\/l\//,'')          
          lang_uri = RDF::URI.new("http://purl.org/NET/marccodes/languages/#{lang_str}#lang")
          @graph << [resource, RDF::DC.language, lang_uri]
        end
      end
    end
    if data['isbn13']
      [*data['isbn13']].each do |isbn13|
        next if isbn13.nil? or isbn13.empty?
	#next unless ISBN_Tools.is_valid_isbn13?(isbn13)
        ISBN_Tools.cleanup!(isbn13)
        next unless ISBN_Tools.is_valid_isbn13?(isbn13)
        @graph << [resource, RDF::BIBO.isbn13, isbn13]
        c_isbn10 = ISBN_Tools.isbn13_to_isbn10(isbn13)
        if c_isbn10
          @graph << [resource, RDF::BIBO.isbn10, c_isbn10]
          @graph << [resource, RDF::OWL.sameAs, RDF::URI.new("http://www4.wiwiss.fu-berlin.de/bookmashup/books/#{c_isbn10}")]
          @graph << [resource, RDF::OWL.sameAs, RDF::URI.new("http://purl.org/NET/book/isbn/#{c_isbn}#book")]
        end        
      end
    end
    
      if data['isbn_13']
        [*data['isbn_13']].each do |isbn13|
          next if isbn13.nil? or isbn13.strip.empty?
  	#next unless ISBN_Tools.is_valid_isbn13?(isbn13)
  	      begin
            ISBN_Tools.cleanup!(isbn13)
          rescue TypeError
            next
          end
          next unless ISBN_Tools.is_valid_isbn13?(isbn13)
          @graph << [resource, RDF::BIBO.isbn13, isbn13]
          c_isbn10 = ISBN_Tools.isbn13_to_isbn10(isbn13)
          if c_isbn10
            @graph << [resource, RDF::BIBO.isbn10, c_isbn10]
            @graph << [resource, RDF::OWL.sameAs, RDF::URI.new("http://www4.wiwiss.fu-berlin.de/bookmashup/books/#{c_isbn10}")]
            @graph << [resource, RDF::OWL.sameAs, RDF::URI.new("http://purl.org/NET/book/isbn/#{c_isbn10}#book")]
          end        
        end
      end    
    if data['url']
      [*data['url']].each do |url|
        next if url.nil? or url.empty?
        begin
          # Let's make sure there's a valid URI here first        
          url_uri = RDF::URI.new(url)
          url_uri.normalize!
          u = URI.parse(url_uri.to_s)
          @graph << [resource, RDF::FOAF.page, uri_uri]
        rescue   
        end
      end
    end
    if data['lc_classifications']
      [*data['lc_classifications']].each do |lcc|
        next if lcc.nil? or lcc.empty?
        lcc.gsub!(/\\/,' ')
        lcc.strip!
        lcc_node = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/lcc/#{lcc.slug}#class")
        lcc_node.normalize!
        @graph << [resource, RDF::DC.subject, lcc_node]
        @graph << [lcc_node, RDF::DCAM.isMemberOf, RDF::DC.LCC]
        
        @graph << [lcc_node, RDF.value, lcc]
        if lcc.upcase =~ /^[A-Z]{1,3}(\s?[1-9][0-9]*|$)/
          lcco = lcc.upcase.match(/^([A-Z]{1,3})/)[1]
          lcco_u = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/lcc/#{lcco}#scheme")
          @graph << [lcco_u, RDF.type, RDF::SKOS.ConceptScheme]
          @graph << [lcc_node, RDF::SKOS.inScheme, lcco_u]
        end
      end
    end
    if data['genres']
      [*data['genres']].each do | genre|
        next if genre.nil? or genre.empty?    
        @graph << [resource, RDF::DC.type, genre.strip_trailing_punct]  
      end
    end
    if data['table_of_contents']
      table_of_contents = []
      [*data['table_of_contents']].each do |toc|
        next unless toc['title'] || toc['value']
        table_of_contents << case
        when toc['title'] then toc['title'].gsub(/\f/,'f').gsub!(/\b/,'')
        when toc['value'] then toc['value'].gsub(/\f/,'f').gsub!(/\b/,'')
        end
      end
      unless table_of_contents.empty?            
        @graph << [resource, RDF::DC.tableOfContents, table_of_contents.join("\n")]
      end
    end
    if data['lccns']
      [*data['lccns']].each do |lccn|
        next if lccn.nil? or lccn.empty?    
        lccn.gsub!(/[^A-z0-9]/,"")
        @graph << [resource, RDF::BIBO.lccn, lccn]

        linked_lccn = RDF::URI.new("http://purl.org/NET/lccn/#{lccn.gsub(/\s/,"").gsub(/\/.*/,"")}#i")
        @graph << [resource, RDF::OWL.sameAs, linked_lccn]
      end
    end
    if data['lccn']
      [*data['lccn']].each do |lccn|
        next if lccn.nil? or lccn.empty?    
        lccn.gsub!(/[^A-z0-9]/,"")
        @graph << [resource, RDF::BIBO.lccn, lccn]

        linked_lccn = RDF::URI.new("http://purl.org/NET/lccn/#{lccn.gsub(/\s/,"").gsub(/\/.*/,"")}#i")
        @graph << [resource, RDF::OWL.sameAs, linked_lccn]
      end
    end  
    if data['uris']
      [*data['uris']].each do |u|
        next if u.nil? or u.empty?
	      begin
          u_uri = RDF::URI.new(u)
          u_uri.normalize!
          @graph << [resource, RDF::BIBO.uri, u_uri]
	      rescue
	        next
	      end
      end
    end
    if data['subtitle'] && !data['subtitle'].empty?
      @graph << [resource, RDF::RDA.otherTitleInformation, data['subtitle']]
    end
  
    if data['publishers']
      [*data['publishers']].each do |publisher|
        next if publisher.nil? or publisher.empty?
        @graph << [resource, RDF::DC11.publisher, publisher]
      end
    end
    if data['authors']
      authors = []
      [*data['authors']].each do |author|
        next if author.nil? or author.empty?
        a = RDF::URI.new("http://openlibrary.org#{author['key']}")
        @graph << [resource, RDF::DC.creator, a]
        authors << a
      end
      # We only need an author list if we have more than one author
      if authors.length > 1
        author_list = gen_author_list(authors)
        @graph << [resource, RDF::BIBO.authorList, author_list]
      end
    end
  
    if data['copyright_date'] && !data['copyright_date'].empty?
      @graph << [resource, RDF::DC.dateCopyrighted, data['copyright_date']]
    end
    if data['description'] and data['description']['value'] and !data['description']['value'].empty?
      data['description']['value'].gsub!(/\f/,'f')
      data['description']['value'].gsub!(/\b/,'')      
      @graph << [resource, RDF::DC.description, data['description']['value']]
    end
    if data['other_titles']
      [*data['other_titles']].each do |alt|
        next if alt.nil? or alt.empty?     
        @graph << [resource, RDF::RDA.variantTitle, alt] 
      end
    end
  
    if data['title'] && !data['title'].empty?
      title = "#{data['title_prefix']}#{data['title']}"
      @graph << [resource, RDF::RDA.titleProper, title.dup]
      if data['subtitle']
        title << "; #{data['subtitle']}"
      end    
      @graph << [resource, RDF::DC.title, title]
    end
  
    if data['dewey_decimal_class']
      [*data['dewey_decimal_class']].each do |ddc|
        next if ddc.nil? or ddc.empty?
        ddc_node = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/ddc/#{ddc.slug}#class")
        ddc_node.normalize!
        @graph << [resource, RDF::DC.subject, ddc_node]
        @graph << [ddc_node, RDF::DCAM.isMemberOf, RDF::DC.DDC]
        @graph << [ddc_node, RDF.value, ddc]
        if ddc =~ /^[0-9]{3}([^0-9]|$)/
          ddc_o = ddc.match(/^([0-9]{3})/)[0]
          ddc_o_u = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/ddc/#{ddc_o}#scheme")
          @graph << [ddc_o_u, RDF.type, RDF::SKOS.ConceptScheme]
          @graph << [ddc_node, RDF::SKOS.inScheme, ddc_o_u]
        end  
      end
    end
    if data['dewry_decimal_class']
      [*data['dewry_decimal_class']].each do |ddc|
        next if ddc.nil? or ddc.empty?
        ddc_node = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/ddc/#{ddc.slug}#class")
        ddc_node.normalize!
        @graph << [resource, RDF::DC.subject, ddc_node]
        @graph << [ddc_node, RDF::DCAM.isMemberOf, RDF::DC.DDC]
        @graph << [ddc_node, RDF.value, ddc]
        if ddc =~ /^[0-9]{3}([^0-9]|$)/
          ddc_o = ddc.match(/^([0-9]{3})/)[0]
          ddc_o_u = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/ddc/#{ddc_o}#scheme")
          @graph << [ddc_o_u, RDF.type, RDF::SKOS.ConceptScheme]
          @graph << [ddc_node, RDF::SKOS.inScheme, ddc_o_u]
        end
      end
    end  
    if data['publish_country'] && !data['publish_country'].empty?
      if data['publish_country'] =~ /^[a-z]*$/ && data['publish_country'].length < 4
        country = RDF::URI.new("http://purl.org/NET/marccodes/#{data['publish_country'].strip}#location")
        @graph << [resource, RDF::RDA.placeOfPublication, country]
      end
    end
    if data['contributions']
      [*data['contributions']].each do |contributor|
        next if contributor.nil? or contributor.empty?
        @graph << [resource, RDF::DC11.contributor, contributor]
      end
    end
    if data['oclc_numbers']
      [*data['oclc_numbers']].each do |oclc_num|
        next if oclc_num.nil? or oclc_num.empty?
        [*oclc_num].each do |onum|
          next unless onum
          onum.gsub!(/[^0-9]/,'')
          @graph << [resource, RDF::BIBO.oclcnum, onum]
          wc = RDF::URI.new("http://worldcat.org/oclc/#{onum}")
          @graph << [resource, RDF::FOAF.page, wc]
        end
      end
    end
  
    if data['pagination']
      [*data['pagination']].each do |pagination|
        next if pagination.nil? or pagination.empty?   
        @graph << [resource, RDF::DC.extent, pagination]   
      end
    end
  
    if data['physical_dimensions'] && !data['physical_dimensions'].empty?  
      @graph << [resource, RDF::RDA.dimensions, data['physical_dimensions']]  
    end
  
    if data['volumes']
      [*data['volumes']].each do | vol |
        next if !vol['key'] or vol['key'].empty?
        @graph << [resource, RDF::BIBO.volume, vol['key']]
      end
    end
  
    if data['subjects']
      [*data['subjects']].each do | subject |
        next if subject.nil? or subject.empty?
        if subject.is_a?(String)
          @graph << [resource, RDF::DC11.subject, subject]
        elsif subject.is_a?(Hash) && subject['key'] && !(subject['key'].nil? || subject['key'].empty?)
          @graph << [resource, RDF::DC.subject, RDF::URI.new(URI_PREFIX+subject['key'])]
        end
      end
    end
  
    if data['ocaid'] && !data['ocaid'].empty? && data['ocaid'].strip.match(/^[A-z0-9]*$/)      
      @graph << [resource, RDF::DC11.identifier, data['ocaid'].strip]
      #['pdf','epub','djvu','mobi'].each do |fmt|
      #  @graph << [resource, RDF::DC.hasFormat, RDF::URI.new("http://www.archive.org/download/#{data['ocaid'].strip}/#{data['ocaid'].strip}.#{fmt}")]
      #end
      #@graph << [resource, RDF::DC.hasFormat, RDF::URI.new("http://www.archive.org/download/#{data['ocaid'].strip}/#{data['ocaid'].strip}_djvu.txt")]
      @graph << [resource, RDF::FOAF.page, "http://www.archive.org/details/#{data['ocaid'].strip}"]
    end
  
    if data['publish_places']
      [*data['publish_places']].each do |place|
        next if place.nil? or place.empty?
        @graph << [resource, RDF::RDA.placeOfPublication, place]
      end
    end
  
    if data['notes']
      [*data['notes']].each do |note|
        next unless note
        if note.is_a?(Hash)
          @graph << [resource, RDF::RDA.note, note['value']] unless note['value'].empty?
        elsif note.is_a?(Array)
          if note[0] == "value" && !note[1].empty?
            @graph << [resource, RDF::RDA.note, note[1]]
          end
        elsif note.is_a?(String) && !note.empty?
          @graph << [resource, RDF::RDA.note, note]
        end
      end
    end
  
    if data['source_records']
      [*data['source_records']].each do | source |
        next if source.nil? or source.empty?
        @graph << [resource, RDF::DC11.source, source]
      end
    end
  
    if data['volume_number']
      @graph << [resource, RDF::BIBO.volume, data['volume_number']]
    end
  
    if data['isbn'] && !data['isbn'].empty?
      [*data['isbn']].each do |isbn|
        next unless isbn
        next unless ISBN_Tools.is_valid_isbn10?(isbn) || ISBN_Tools.is_valid_isbn13?(isbn)
        ISBN_Tools.cleanup!(isbn)
        @graph << [resource, RDF::BIBO.isbn, isbn]
        if isbn.length == 10
          @graph << [resource, RDF::BIBO.isbn10, isbn]
          @graph << [resource, RDF::OWL.sameAs, RDF::URI.new("http://www4.wiwiss.fu-berlin.de/bookmashup/books/#{isbn}")]
          @graph << [resource, RDF::OWL.sameAs, RDF::URI.new("http://purl.org/NET/book/isbn/#{isbn}#book")]        
          c_isbn13 = ISBN_Tools.isbn10_to_isbn13(isbn)
          if c_isbn13    
            @graph << [resource, RDF::BIBO.isbn13, c_isbn13]
          end
        elsif isbn.length == 13
          @graph << [resource, RDF::BIBO.isbn13, isbn]
          c_isbn10 = ISBN_Tools.isbn13_to_isbn10(isbn)
          if c_isbn10
            @graph << [resource, RDF::BIBO.isbn10, c_isbn10]
            @graph << [resource, RDF::OWL.sameAs, RDF::URI.new("http://www4.wiwiss.fu-berlin.de/bookmashup/books/#{c_isbn10}")]
            @graph << [resource, RDF::OWL.sameAs, RDF::URI.new("http://purl.org/NET/book/isbn/#{c_isbn}#book")]          
          end
        end
      end
    end
  
    if data['number_of_pages']
      @graph << [resource, RDF::BIBO.pages, data['number_of_pages']]
    end
  
    if data['oclc_number'] && !data['oclc_number'].empty?
      [*data['oclc_number']].each do |onum|
        next unless onum
        onum.gsub!(/[^0-9]/,'')
        @graph << [resource, RDF::BIBO.oclcnum, onum]
        wc = RDF::URI.new("http://worldcat.org/oclc/#{onum}")
        @graph << [resource, RDF::FOAF.page, wc]
      end    
    end
  
  
    if data['publish_date'] && !data['publish_date'].empty?
      @graph << [resource, RDF::DC.issued, data['publish_date']]
    end
  
    if data['edition_name'] && !data['edition_name'].empty?
      @graph << [resource, RDF::BIBO.edition, data['edition_name']]
    end
  
    if data['isbn_10']
      [*data['isbn_10']].each do | isbn10 |
        next if isbn10.nil? or isbn10.empty?
	next unless ISBN_Tools.is_valid_isbn10?(isbn10)
        ISBN_Tools.cleanup!(isbn10) if isbn10
        @graph << [resource, RDF::BIBO.isbn10, isbn10]
        @graph << [resource, RDF::OWL.sameAs, RDF::URI.new("http://www4.wiwiss.fu-berlin.de/bookmashup/books/#{isbn10}")]
        @graph << [resource, RDF::OWL.sameAs, RDF::URI.new("http://purl.org/NET/book/isbn/#{isbn10}#book")]
        c_isbn13 = ISBN_Tools.isbn10_to_isbn13(isbn10)
        if c_isbn13      
          @graph << [resource, RDF::BIBO.isbn13, c_isbn13]
        end
      end
    end
  
    if data['work_title']
      [*data['work_title']].each do |work_title|
        next if work_title.nil? or work_title.empty?
        @graph << [resource, RDF::RDA.titleOfTheWork, work_title]
      end
    end
  
    if data['by_statement'] && !data['by_statement'].empty?
      @graph << [resource, RDF::RDA.statementOfResponsibility, data['by_statement']]
    end
  
    if data['by_statements']
      [*data['by_statements']].each do |by|
        next if by.nil? or by.empty?
        @graph << [resource, RDF::RDA.statementOfResponsibility, by]
      end    
    end  
  
    if data['works']
      [*data['works']].each do |work|
        next if work.nil? or work.empty?
        w = RDF::URI.new(URI_PREFIX+work['key'])
        @graph << [resource, RDF::DC.isVersionOf, w]
        @graph << [resource, RDF::OV.commonManifestation, w]
        @graph << [w, RDF::DC.hasVersion, resource]
        @graph << [w, RDF::OV.commonManifestation, resource]        
      end
    end
    
    if data['covers']
      [*data['covers']].each do |cover|
        next if cover.nil?
        ["S","M","L"].each do |size|
          @graph << [resource, RDF::FOAF.depiction, RDF::URI.new("http://covers.openlibrary.org/b/id/#{cover}-#{size}.jpg")]
        end
      end
    end
  end

  def add_work_to_graph(data)
    resource = RDF::URI.new(URI_PREFIX+data['key'])
    @graph << [resource, RDF.type, RDF::FRBR.Work]
    if data['title'] && !data['title'].empty?
      @graph << [resource, RDF::DC.title, data['title']]
    end  
    if data['subjects']
      [*data['subjects']].each do | subject |
        next if subject.nil? or subject.empty?
        if subject.is_a?(String)
          @graph << [resource, RDF::DC11.subject, subject]
        elsif subject.is_a?(Hash) && subject['key'] && !(subject['key'].nil? || subject['key'].empty?)
          @graph << [resource, RDF::DC.subject, RDF::URI.new(URI_PREFIX+subject['key'])]
        end
      end
    end  
    if data['first_publish_date'] && !data['first_publish_date'].empty?
      @graph << [resource, RDF::DC.created, data['first_publish_date']]
    end
    if data['authors']
      authors = []
      [*data['authors']].each do |au|
        next if !au['author'] or !au['author']['key'] or au['author']['key'].nil? or au['author']['key'].empty?
        a = RDF::URI.new(URI_PREFIX+au['author']['key'])
        @graph << [resource, RDF::DC.creator, a]
        @graph << [a, RDF::FOAF.made, resource]
        authors << a
      end
      # We only need an author list if we have more than one author
      if authors.length > 1
        author_list = gen_author_list(authors)
        @graph << [resource, RDF::BIBO.authorList, author_list]
      end    
    end
    
    if data['covers']
      [*data['covers']].each do |cover|
        next if cover.nil?
        ["S","M","L"].each do |size|
          @graph << [resource, RDF::FOAF.depiction, RDF::URI.new("http://covers.openlibrary.org/w/id/#{cover}-#{size}.jpg")]
        end
      end
    end    
  end
  
  def parse_lines
    @lines.each do |line|
      (type,id,rev,date,data) = line.split("\t")
      elements = JSON.parse(data)
      if elements['latest_revision']
        next unless elements['latest_revision'] == elements['revision']
      end
      case type
      when "/type/edition" then add_edition_to_graph(elements)
      when "/type/author" then add_author_to_graph(elements)    
      when "/type/work" then add_work_to_graph(elements)        
      else
        next
      end
 
    end
    @lines = [] 
  end  
  
  def write_graph_to_file
    ntriples = RDF::Writer.for(:ntriples).buffer do |writer|
      @graph.each_statement do |statement|
        writer << statement
      end
    end
    @file << ntriples
    @graph = RDF::Graph.new
  end
  
  def to_ntriples
    RDF::Writer.for(:ntriples).buffer do |writer|
      #@graph.each_statement do |statement|
      @graph.each do |statement|
        writer << statement
      end
    end
  end    
  # def to_ntriples
  #   @graph.to_ntriples
  # end
  def clear_graph
    #@graph = RDF::Graph.new
    @graph = []
  end  
  
  def new_file
    @file.close if @file
    puts "Starting new output file at openlibrary-#{DateTime.now.strftime("%Y-%m-%d")}-#{@file_number}.nt.gz."
    @file_number += 1
    @file = Zlib::GzipWriter.open("#{ARGV[1]}/openlibrary-#{DateTime.now.strftime("%Y-%m-%d")}-#{@file_number}.nt.gz")  
  end

end



triplers = []
@file = Zlib::GzipWriter.open("#{ARGV[1]}/openlibrary-#{DateTime.now.strftime("%Y-%m-%d")}.nt.gz") 
(1..numthreads).each do |t|
  triplers << Tripler.new
end

def add_to_triplers(triplers, line)
  triplers.each do |tripler|
    unless tripler.lines.length > 1001
      tripler.lines << line
      return false
    end
  end
  triplers.last.lines << line
  true
end

def parse_lines_or_warm_threads(tripler)
  warm = false
  until warm
    begin
      tripler.parse_lines
      warm = true
    rescue NameError => e
      puts "Constants still not initialized:  #{e}"
    end
  end
end

def start_threading(triplers)
  #puts "Start threading"
  
  triplers.threach(triplers.length) do |tripler|
  #triplers.each do |tripler|
    #parse_lines_or_warm_threads(tripler)
    tripler.parse_lines
  end

  triplers.each do |tripler|
    begin
      @file << tripler.to_ntriples
    rescue StandardError=>e
      puts e
      raise
    end      
    tripler.clear_graph
  end
  #puts "End threading"
end  

i = 0
while line = file.gets
  i += 1
  if add_to_triplers(triplers, line)
    start_threading(triplers) 
    puts i
  end
end

triplers.each do |tripler|
  begin
    @file << tripler.to_ntriples
  rescue StandardError=>e
    puts e
    raise
  end
end

@file.close





