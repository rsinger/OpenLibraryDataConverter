require 'rubygems'
require 'jruby/path_helper'
require 'rdf'
require 'rdf_objects'

require 'isbn/tools'
require 'zlib'
require 'json'


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

input_file = File.new('/Users/rosssinger/Downloads/ol_dump_2010-06-30.txt.gz', 'r')
file = Zlib::GzipReader.new(input_file)

i = 0
Curie.add_prefixes! :skos=>"http://www.w3.org/2004/02/skos/core#",
 :owl=>'http://www.w3.org/2002/07/owl#', :dcam=>"http://purl.org/dc/dcam/", :bio=>"http://purl.org/vocab/bio/0.1/",
 :dcterms => 'http://purl.org/dc/terms/', :bibo => 'http://purl.org/ontology/bibo/', :rda=>"http://RDVocab.info/Elements/",
 :frbr=>"http://purl.org/vocab/frbr/core#", :rdag2=>"http://RDVocab.info/ElementsGr2/"


URI_PREFIX = "http://openlibrary.org"


class Tripler
  attr_reader :file_prefix, :file_number, :file, :graph, :bad_graph
  attr_accessor :lines
  def initialize(prefix)
    @file_prefix = prefix
    @file_number = 0
    @graph = RDFObject::Collection.new
    @bad_graph = RDFObject::Collection.new
    new_file
    @i = 0
    @j = 0
    @lines = []
  end

  def gen_author_list(authors)
    rest = "[rdf:nil]"
    authors.reverse.each do | au |
      n = RDFObject::BlankNode.new
      @graph[n.uri] = n
      n.relate("[rdf:first]", au)
      n.relate("[rdf:rest]", rest)
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
    resource = @graph.find_or_create(URI_PREFIX+data['key'])
    resource.relate("[rdf:type]", "[foaf:Agent]")

    if data['personal_name'] && !data['personal_name'].empty?
      resource.assert("[foaf:name]", RDF::Literal.new(data['personal_name']))
      if data['name'] && !data['name'].empty?
        resource.assert("[skos:altLabel]", RDF::Literal.new(data['name']))
      end
    elsif data['name'] && !data['name'].empty?
      resource.assert("[foaf:name]", RDF::Literal.new(data['name']))
    end
    if data['birth_date'] && !data['birth_date'].empty?
      node = RDFObject::BlankNode.new
      @graph[node.uri] = node
      node.relate("[rdf:type]", "[bio:Birth]")
      node.relate("[bio:principal]", resource)
      resource.relate("[bio:event]", node)
      node.assert("[dcterms:date]", data['birth_date'])
    end
    if data['death_date'] && !data['death_date'].empty?
      node = RDFObject::BlankNode.new
      @graph[node.uri] = node
      node.relate("[rdf:type]", "[bio:Death]")
      node.relate("[bio:principal]", resource)
      resource.relate("[bio:event]", node)
      node.assert("[dcterms:date]", data['death_date'])
    end  
    if data['website'] && !data['website'].empty?
      if url = sanitize_url(data['website'])
        begin
          hp = Addressable::URI.parse(url)
          hp.normalize!
          u = URI.parse(hp.to_s)
          resource.relate("[foaf:homepage]", hp.to_s)
        rescue

        end
      end
    end
    if data['bio'] && !data['bio'].empty?
      if data['bio'].is_a?(String)
        resource.assert("[bio:olb]", data['bio'])
      elsif data['bio'].is_a?(Hash) && data['bio']['value'] && !data['bio']['value'].empty?
        resource.assert("[bio:olb]", data['bio']['value'])
      end
    end
  
    if data['title'] && !data['title'].empty?
      resource.assert('[rdag2:titleOfThePerson]', data['title'])
    end
  
    if data['alternate_names'] && !data['alternate_names'].empty?
      [*data['alternate_names']].each do |alt_name|
        next if alt_name.nil? or alt_name.empty?
        resource.assert("[dcterms:alternative]", alt_name)
      end
    end
    if data['wikipedia'] && !data['wikipedia'].empty?
      [*data['wikipedia']].each do |wik|
        next if wik.nil? or wik.empty?
        next unless w = sanitize_url(wik)
        begin
          wp = Addressable::URI.parse(w)
          wp.normalize!
          u = URI.parse(wp.to_s)
          resource.relate("[foaf:page]", wp.to_s)
          if wp.host =~ /wikipedia\.org/
            wp.host = "dbpedia.org"
            wp.path.sub!(/\/wiki\//,"/resource/")
            resource.relate("[owl:sameAs]", wp.to_s)
          end
        rescue

        end
      end
    end
    if data['fuller_name'] && !data['fuller_name'].empty?
      [*data['fuller_name']].each do |fn|
        next if fn.nil? or fn.empty?
        resource.assert("[rdag2:fullerFormOfName]", fn)
      end
    end
  end  

  def add_edition_to_graph(data)
    resource = @graph.find_or_create(URI_PREFIX+data['key'])
    resource.relate("[rdf:type]", "[frbr:Manifestation]")

    if data['languages']
      data['languages'].each do |lang|
        if lang['key']
          lang_uri = "http://purl.org/NET/marccodes/languages/#{lang['key'].sub(/^\/l\//,"")}#lang"
          resource.relate("[dcterms:language]", lang_uri)
        end
      end
    end
    if data['isbn13']
      [*data['isbn13']].each do |isbn13|
        next if isbn13.nil? or isbn13.empty?
        resource.assert("[bibo:isbn13]", isbn13)
        c_isbn10 = ISBN_Tools.isbn13_to_isbn10(isbn13)
        if c_isbn10
          resource.assert("[bibo:isbn10]", isbn10)
        end        
      end
    end
    if data['url']
      [*data['url']].each do |url|
        next if url.nil? or url.empty?
        begin
          # Let's make sure there's a valid URI here first        
          url_uri = Addressable::URI.parse(url)
          url_uri.normalize!
          u = URI.parse(url_uri)
          resource.relate("[foaf:page]", url_uri)
        rescue
          url_uri = Addressable::URI.parse(url)
          bgr = @bad_graph.find_or_create(resource.uri)
          bgr.relate("[foaf:page]", url_uri.to_s)    
        end
      end
    end
    if data['lc_classifications']
      [*data['lc_classifications']].each do |lcc|
        next if lcc.nil? or lcc.empty?
        lcc_node = Addressable::URI.parse("http://api.talis.com/stores/openlibrary/items/#{lcc.slug}#lcc")
        lcc_node.normalize!
        n = @graph.find_or_create(lcc_node.to_s)
        resource.relate("[dcterms:subject]", n)
        n.relate("[dcam:isMemberOf]", "[dcterms:LCC]")
        n.assert("[rdf:value]", lcc)
      end
    end
    if data['genres']
      [*data['genres']].each do | genre|
        next if genre.nil? or genre.empty?    
        resource.assert("[dcterms:type]", genre.strip_trailing_punct)  
      end
    end
    if data['table_of_contents']
      table_of_contents = []
      [*data['table_of_contents']].each do |toc|
        next unless toc['title'] || toc['value']
        table_of_contents << case
        when toc['title'] then toc['title']
        when toc['value'] then toc['value']
        end
      end
      unless table_of_contents.empty?      
        resource.assert("[dcterms:tableOfContents]", table_of_contents.join("\n"))
      end
    end
    if data['lccns']
      [*data['lccns']].each do |lccn|
        next if lccn.nil? or lccn.empty?    
        resource.assert("[bibo:lccn]", lccn)  
        linked_lccn = "http://purl.org/NET/lccn/#{lccn.gsub(/\s/,"").gsub(/\/.*/,"")}#i"
        resource.relate("[owl:sameAs]", linked_lccn)
      end
    end
    if data['lccn']
      [*data['lccn']].each do |lccn|
        next if lccn.nil? or lccn.empty?    
        resource.assert("[bibo:lccn]", lccn)  
        linked_lccn = "http://purl.org/NET/lccn/#{lccn.gsub(/\s/,"").gsub(/\/.*/,"")}#i"
        resource.relate("[owl:sameAs]", linked_lccn)
      end
    end  
    if data['uris']
      [*data['uris']].each do |u|
        next if u.nil? or u.empty?
        resource.assert("[bibo:uri]", u)
      end
    end
    if data['subtitle'] && !data['subtitle'].empty?
      resource.assert("[rda:otherTitleInformation]", data['subtitle'])
    end
  
    if data['publishers']
      [*data['publishers']].each do |publisher|
        next if publisher.nil? or publisher.empty?
        resource.assert("[dc:publisher]", publisher)
      end
    end
    if data['authors']
      authors = []
      [*data['authors']].each do |author|
        next if author.nil? or author.empty?
        a = @graph.find_or_create("http://openlibrary.org#{author['key']}")
        resource.relate("[dcterms:creator]", a)
        authors << a
      end
      # We only need an author list if we have more than one author
      if authors.length > 1
        author_list = gen_author_list(authors)
        resource.relate("[bibo:authorList]", author_list)
      end
    end
  
    if data['copyright_date'] && !data['copyright_date'].empty?
      resource.assert("[dcterms:dateCopyrighted]", data['copyright_date'])
    end
    if data['description'] and data['description']['value'] and !data['description']['value'].empty?
      resource.assert("[dcterms:description]", data['description']['value'])
    end
    if data['other_titles']
      [*data['other_titles']].each do |alt|
        next if alt.nil? or alt.empty?      
        resource.assert("[rda:variantTitle]", alt)
      end
    end
  
    if data['title'] && !data['title'].empty?
      title = "#{data['title_prefix']}#{data['title']}"
      resource.assert("[rda:titleProper]", title)
      if data['subtitle']
        title << "; #{data['subtitle']}"
      end    
      resource.assert("[dc:title]", title)
    end
  
    if data['dewey_decimal_class']
      [*data['dewey_decmimal_class']].each do |ddc|
        next if ddc.nil? or ddc.empty?
        ddc_node = Addressable::URI.parse("http://api.talis.com/stores/openlibrary/items/#{ddc.slug}#ddc")
        ddc_node.normalize!
        n = @graph.find_or_create(ddc_node.to_s)
        resource.relate("[dcterms:subject]", n)
        n.relate("[dcam:isMemberOf]", "[dcterms:DDC]")
        n.assert("[rdf:value]", ddc)
      end
    end
    if data['dewry_decimal_class']
      [*data['dewry_decmimal_class']].each do |ddc|
        next if ddc.nil? or ddc.empty?
        ddc_node = Addressable::URI.parse("http://api.talis.com/stores/openlibrary/items/#{ddc.slug}#ddc")
        ddc_node.normalize!
        n = @graph.find_or_create(ddc_node.to_s)
        resource.relate("[dcterms:subject]", n)
        n.relate("[dcam:isMemberOf]", "[dcterms:DDC]")
        n.assert("[rdf:value]", ddc)
      end
    end  
    if data['publish_country'] && !data['publish_country'].empty?
      if data['publish_country'] =~ /^[a-z]*$/ && data['publish_country'].length < 4
        country = "http://purl.org/NET/marccodes/#{data['publish_country'].strip}#location"
        resource.relate("[rda:placeOfPublication]", country)    
      end
    end
    if data['contributions']
      [*data['contributions']].each do |contributor|
        next if contributor.nil? or contributor.empty?
        resource.assert("[dc:contributor]", contributor)
      end
    end
    if data['oclc_numbers']
      [*data['oclc_numbers']].each do |oclc_num|
        next if oclc_num.nil? or oclc_num.empty?
        if oclc_num.is_a?(Array)
          oclc_num.each {|onum| resource.assert("[bibo:oclcnum]", onum) }
        else
          resource.assert("[bibo:oclcnum]", oclc_num)
        end      
      end
    end
  
    if data['pagination']
      [*data['pagination']].each do |pagination|
        next if pagination.nil? or pagination.empty?      
        resource.assert("[dcterms:extent]", pagination)
      end
    end
  
    if data['physical_dimensions'] && !data['physical_dimensions'].empty?    
      resource.assert("[rda:dimensions]", data['physical_dimensions'])
    end
  
    if data['volumes']
      [*data['volumes']].each do | vol |
        next if !vol['key'] or vol['key'].empty?
        resource.assert("[bibo:volume]", vol['key'])
      end
    end
  
    if data['subjects']
      [*data['subjects']].each do | subject |
        next if subject.nil? or subject.empty?
        if subject.is_a?(String)
          resource.assert("[dc:subject]", subject)
        elsif subject.is_a?(Hash) && subject['key'] && !(subject['key'].nil? || subject['key'].empty?)
          resource.relate("[dcterms:subject]", URI_PREFIX+subject['key'])
        end
      end
    end
  
    if data['ocaid'] && !data['ocaid'].empty?
      resource.assert("[dc:identifier]", data['ocaid'])
    end
  
    if data['publish_places']
      [*data['publish_places']].each do |place|
        next if place.nil? or place.empty?
        resource.assert("[rda:placeOfPublication]", place)
      end
    end
  
    if data['notes']
      [*data['notes']].each do |note|
        next unless note
        if note.is_a?(Hash)
          resource.assert("[rda:note]", note['value']) unless note['value'].empty?
        elsif note.is_a?(Array)
          if note[0] == "value" && !note[1].empty?
            resource.assert("[rda:note]", note[1])
          end
        elsif note.is_a?(String) && !note.empty?
          resource.assert("[rda:note]", note)
        end
      end
    end
  
    if data['source_records']
      [*data['source_records']].each do | source |
        next if source.nil? or source.empty?
        resource.assert("[dc:source]", source)
      end
    end
  
    if data['volume_number']
      resource.assert("[bibo:volume]", data['volume_number'])
    end
  
    if data['isbn'] && !data['isbn'].empty?
      resource.assert("[bibo:isbn]", data['isbn'])
      if data['isbn'].length == 10
        resource.assert("[bibo:isbn10]", data['isbn'])
        c_isbn13 = ISBN_Tools.isbn10_to_isbn13(data['isbn'])
        if c_isbn13    
          resource.assert("[bibo:isbn13]", c_isbn13)    
        end
      elsif data['isbn'].length == 13
        resource.assert("[bibo:isbn13]", data['isbn'])
        c_isbn10 = ISBN_Tools.isbn13_to_isbn10(data['isbn'])
        if c_isbn10
          resource.assert("[bibo:isbn10]", c_isbn10)
        end
      end
    end
  
    if data['number_of_pages']
      resource.assert("[bibo:pages]", data['number_of_pages'])
    end
  
    if data['oclc_number'] && !data['oclc_number'].empty?
      if data['oclc_number'].is_a?(Array)
        data['oclc_number'].each {|onum| resource.assert("[bibo:oclcnum]", onum) }
      else
        resource.assert("[bibo:oclcnum]", data['oclc_number'])
      end    
    end
  
  
    if data['publish_date'] && !data['publish_date'].empty?
      resource.assert("[dcterms:issued]", data['publish_date'])
    end
  
    if data['edition_name'] && !data['edition_name'].empty?
      resource.assert("[bibo:edition]", data['edition_name'])
    end
  
    if data['isbn_10']
      [*data['isbn_10']].each do | isbn10 |
        next if isbn10.nil? or isbn10.empty?
        resource.assert("[bibo:isbn10]", isbn10)
        c_isbn13 = ISBN_Tools.isbn10_to_isbn13(isbn10)
        if c_isbn13      
          resource.assert("[bibo:isbn13]", c_isbn13)
        end
      end
    end
  
    if data['work_title']
      [*data['work_title']].each do |work_title|
        next if work_title.nil? or work_title.empty?
        resource.assert("[rda:titleOfTheWork]", work_title)
      end
    end
  
    if data['by_statement'] && !data['by_statement'].empty?
      resource.assert("[rda:statementOfResponsibility]", data['by_statement'])
    end
  
    if data['by_statements']
      [*data['by_statements']].each do |by|
        next if by.nil? or by.empty?
        resource.assert("[rda:statementOfResponsibility]", by)
      end    
    end  
  
    if data['works']
      [*data['works']].each do |work|
        next if work.nil? or work.empty?
        w = @graph.find_or_create(URI_PREFIX+work['key'])
        resource.relate("[dcterms:isVersionOf]", w)
        w.relate("[dcterms:hasVersion]", resource)
      end
    end
  end

  def add_work_to_graph(data)
    resource = @graph.find_or_create(URI_PREFIX+data['key'])
    resource.relate("[rdf:type]", "[frbr:Work]")
    if data['title'] && !data['title'].empty?
      resource.assert("[dc:title]", data['title'])
    end  
    if data['subjects']
      [*data['subjects']].each do | subject |
        next if subject.nil? or subject.empty?
        if subject.is_a?(String)
          resource.assert("[dc:subject]",subject)
        elsif subject.is_a?(Hash) && subject['key'] && !(subject['key'].nil? || subject['key'].empty?)
          resource.relate("[dcterms:subject]", URI_PREFIX+subject['key'])
        end
      end
    end  
    if data['first_publish_date'] && !data['first_publish_date'].empty?
      resource.assert("[dcterms:created]", data['first_publish_date'])
    end
    if data['authors']
      authors = []
      [*data['authors']].each do |au|
        next if !au['author'] or !au['author']['key'] or au['author']['key'].nil? or au['author']['key'].empty?
        a = @graph.find_or_create(URI_PREFIX+au['author']['key'])
        resource.relate("[dcterms:creator]", a)
        a.relate("[foaf:made]", resource)
        authors << a
      end
      # We only need an author list if we have more than one author
      if authors.length > 1
        author_list = gen_author_list(authors)
        resource.relate("[bibo:authorList]", author_list)
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

      @i += 1
      if @i == 1000
        @j += @i
        puts @j
        write_graph_to_file
        if @j.to_s =~ /000000$/ || @j.to_s =~ /500000$/          
          new_file
        end
        @i = 0
        
        @bad_graph.clear
      end   
    end
    @lines = [] 
  end  
  
  def write_graph_to_file
    @file << @graph.to_ntriples  
    @graph = RDFObject::Collection.new
  end
  
  def new_file
    @file.close if @file
    puts "Starting new output file at openlibrary-#{@file_prefix}-#{@file_number}.nt."
    @file_number += 1
    @file = File.new("/Volumes/External/shared/open-library/openlibrary-#{@file_prefix}-#{@file_number}.nt", 'w')  
  end

end



#j = 0
t1 = Tripler.new('a')
t2 = Tripler.new('b')
t3 = Tripler.new('c')
while line = file.gets
  #if j < file_number
  #  j += 1
  #  next
  #end
  if t1.lines.length < 100001
    t1.lines << line
  elsif t2.lines.length < 100001
    t2.lines << line
  elsif t3.lines.length < 100001
    t3.lines << line
  else
    puts "Start threading"
    threads = []
    [t1,t2,t3].each do |tripler|

      threads << Thread.new{
        require 'jruby/path_helper'        
        tripler.parse_lines
      }
    end
    threads.each {|th| th.join }

    puts "End threading"
    t1.lines << line
  end

end
t1.write_graph_to_file
t1.file.close
t2.write_graph_to_file
t2.file.close
t3.write_graph_to_file
t3.file.close






