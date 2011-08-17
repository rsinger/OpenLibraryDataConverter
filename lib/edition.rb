module OpenLibrary
  class Edition
    include OpenLibrary
    attr_reader :statements
    def initialize(data)
      @data = data
      set_identifier
      @statements = [RDF::Statement.new(@uri, RDF.type, RDF::BIBO.Book)]    
      @generic_fields = {
        'subtitle'=>RDF::RDA.otherTitleInformation, 
        'publishers'=>RDF::DC11.publisher, 
        'copyright_date'=>RDF::DC.dateCopyrighted,
        'other_titles'=>RDF::RDA.variantTitle,
        'contributions'=>RDF::DC11.contributor,
        'pagination'=>RDF::DC.extent,
        'physical_dimensions'=>RDF::RDA.dimensions,
        'publish_places'=>RDF::RDA.placeOfPublication,
        'source_records'=>RDF::DC11.source,
        'volume_number'=>RDF::BIBO.volume,
        'number_of_pages'=>RDF::BIBO.pages,
        'publish_date'=>RDF::DC.issued,
        'edition_name'=>RDF::BIBO.edition,
        'work_title'=>RDF::RDA.titleOfTheWork,
        'by_statement'=>RDF::RDA.statementOfResponsibility,
        'by_statements'=>RDF::RDA.statementOfResponsibility
        }      
    end
    def parse_data
      @data.keys.each do |key|
        if self.respond_to?("parse_#{key}".to_sym)
          self.send("parse_#{key}".to_sym, @data[key])
        elsif @generic_fields[key]
          self.parse_generic_field(key, @data[key])
        end
      end      
    end
    
    def parse_languages(languages)
      languages.each do |lang|
        if lang['key']
          lang_str = lang['key']
          lang_str.strip!
          lang_str.sub!(/^\/languages\//,'')
          lang_str.sub!(/^\/l\//,'')          
          lang_uri = RDF::URI.new("http://purl.org/NET/marccodes/languages/#{lang_str}#lang")
          add(@uri, RDF::DC.language, lang_uri)
        end
      end
    end   
    
    def parse_isbn(isbns) 
      [*isbns].each do |isbn|
        next unless isbn
        next unless ISBN_Tools.is_valid_isbn10?(isbn) || ISBN_Tools.is_valid_isbn13?(isbn)
        ISBN_Tools.cleanup!(isbn)
        add(@uri, RDF::BIBO.isbn, isbn)
        if isbn.length == 10
          add(@uri, RDF::BIBO.isbn10, isbn)
          add(@uri, RDF::OWL.sameAs, RDF::URI.new("http://www4.wiwiss.fu-berlin.de/bookmashup/books/#{isbn}"))
          add(@uri, RDF::OWL.sameAs, RDF::URI.new("http://purl.org/NET/book/isbn/#{isbn}#book"))        
          c_isbn13 = ISBN_Tools.isbn10_to_isbn13(isbn)
          if c_isbn13    
            add(@uri, RDF::BIBO.isbn13, c_isbn13)
          end
        elsif isbn.length == 13
          add(@uri, RDF::BIBO.isbn13, isbn)
          c_isbn10 = ISBN_Tools.isbn13_to_isbn10(isbn)
          if c_isbn10
            add(@uri, RDF::BIBO.isbn10, c_isbn10)
            add(@uri, RDF::OWL.sameAs, RDF::URI.new("http://www4.wiwiss.fu-berlin.de/bookmashup/books/#{c_isbn10}"))
            add(@uri, RDF::OWL.sameAs, RDF::URI.new("http://purl.org/NET/book/isbn/#{c_isbn10}#book"))          
          end
        end
      end      
    end
    
    alias :parse_isbn10 :parse_isbn
    alias :parse_isbn13 :parse_isbn    
    alias :parse_isbn_10 :parse_isbn    
    alias :parse_isbn_13 :parse_isbn    
    
    def parse_uri(uri, predicate)
      [*uri].each do |url|
        next if url.nil? or url.empty?
        begin
          # Let's make sure there's a valid URI here first        
          url_uri = RDF::URI.new(url)
          url_uri.normalize!
          u = URI.parse(url_uri.to_s)
          return if url_uri.relative?
          add(@uri, predicate, uri_uri)
        rescue   
        end
      end      
    end
    
    def parse_url(url)
      parse_uri(url, RDF::FOAF.Page)
    end
    
    def parse_uris(uri)
      parse_uri(uri, RDF::BIBO.uri)
    end
    
    def parse_lc_classifications(lc_class)
      [*lc_class].each do |lcc|
        next if lcc.nil? or lcc.empty?
        lcc.gsub!(/\\/,' ')
        lcc.strip!
        lcc_node = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/lcc/#{lcc.slug}#class")
        lcc_node.normalize!
        add(@uri, RDF::DC.subject, lcc_node)
        add(lcc_node, RDF::DCAM.isMemberOf, RDF::DC.LCC)

        add(lcc_node, RDF.value, lcc)
        if lcc.upcase =~ /^[A-Z]{1,3}(\s?[1-9][0-9]*|$)/
          lcco = lcc.upcase.match(/^([A-Z]{1,3})/)[1]
          lcco_u = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/lcc/#{lcco}#scheme")
          add(lcco_u, RDF.type, RDF::SKOS.ConceptScheme)
          add(lcc_node, RDF::SKOS.inScheme, lcco_u)
        end
      end            
    end
    
    def parse_genres(genres)
      [*genres].each do | genre|
        next if genre.nil? or genre.empty?    
        add(@uri, RDF::DC.type, genre.strip_trailing_punct)
      end      
    end
    
    def parse_table_of_contents(tocs)
      table_of_contents = []
      [*tocs].each do |toc|
        next unless toc['title'] || toc['value']
        table_of_contents << case
        when toc['title'] then toc['title'].gsub(/\f/,'f').gsub(/\b/,'').gsub(/[[:cntrl:]]/, "")
        when toc['value'] then toc['value'].gsub(/\f/,'f').gsub(/\b/,'').gsub(/[[:cntrl:]]/, "")
        end
      end
      unless table_of_contents.empty?            
        add(@uri, RDF::DC.tableOfContents, table_of_contents.join("\n"))
      end      
    end
    
    def parse_lccns(lccns)
      [*lccns].each do |lccn|
        next if lccn.nil? or lccn.empty?    
        lccn.gsub!(/[^\w\d]/,"")
        lccn.gsub!(/\^/,"")

        next unless lccn =~ /^\w{0,3}\d*$/
        add(@uri, RDF::BIBO.lccn, lccn)

        linked_lccn = RDF::URI.new("http://purl.org/NET/lccn/#{lccn}#i")          
        add(@uri, RDF::OWL.sameAs, linked_lccn)
        add(@uri, RDF::OWL.sameAs, RDF::URI.new("info:lccn/#{lccn}"))
      end      
    end
    
    alias :parse_lccn :parse_lccns

    def parse_generic_field(field, values)
      return unless @generic_fields[field]

      [*values].each do |value|
        next if value.nil? || (value.respond_to?(:empty?) && value.empty?)
        add(@uri, @generic_fields[field], value)
      end
    end
    
    def parse_authors(auths)
      authors = []
      [*auths].each do |author|
        next if author.nil? or author.empty?
        a = RDF::URI.new("http://openlibrary.org#{author['key']}")
        add(@uri, RDF::DC.creator, a)
        authors << a
        if DB.sismember "pending", author['key']
          DB.append author['key'], "||#{@uri.to_s}"
        elsif auth_list = DB.get(author['key'])
          auth_list.split("||").each do |auth|
            add(@uri, RDF::OL.author, auth)
          end          
        else
          DB.set author['key'], @uri.to_s
          DB.sadd "pending", author['key']
        end        
      end
      # We only need an author list if we have more than one author
      if authors.length > 1
        author_list = Author.gen_author_list(authors)
        author_list.each_pair do |k,v|
          add(@uri, RDF::BIBO.authorList, k)
          v.each do |list_members|
            add(list_members[0], list_members[1], list_members[2])
          end
        end
      end
    end

    def parse_description(desc)
      if desc['value'] and !desc['value'].empty?
        desc['value'].gsub!(/\f/,'f')
        desc['value'].gsub!(/\b/,'')      
        add(@uri, RDF::DC.description, desc['value'])
      end
    end

    def parse_title(t)
      unless t.empty?
        title = "#{@data['title_prefix']}#{t}"
        add(@uri, RDF::RDA.titleProper, title.dup)
        if @data['subtitle']
          title << "; #{@data['subtitle']}"
        end    
        add(@uri, RDF::DC.title, title)
      end
    end
    
    def parse_subtitle(subtitle)
      unless subtitle.empty?
        add(@uri, RDF::RDA.otherTitleInformation, subtitle)
      end
    end

    def parse_dewey_decimal_class(ddcs)
      [*ddcs].each do |ddc|
        next if ddc.nil? or ddc.empty?
        ddc_node = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/ddc/#{ddc.slug}#class")
        ddc_node.normalize!
        add(@uri, RDF::DC.subject, ddc_node)
        add(ddc_node, RDF::DCAM.isMemberOf, RDF::DC.DDC)
        add(ddc_node, RDF.value, ddc)
        if ddc =~ /^[0-9]{3}([^0-9]|$)/
          ddc_o = ddc.match(/^([0-9]{3})/)[0]
          ddc_o_u = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/ddc/#{ddc_o}#scheme")
          add(ddc_o_u, RDF.type, RDF::SKOS.ConceptScheme)
          add(ddc_node, RDF::SKOS.inScheme, ddc_o_u)
        end  
      end
    end
    
    alias :parse_dewry_decimal_class :parse_dewey_decimal_class

    def parse_publish_country(pub_country)
      return if pub_country.empty?
      if pub_country =~ /^[a-z]*$/ && pub_country.length < 4
        country = RDF::URI.new("http://purl.org/NET/marccodes/#{pub_country.strip}#location")
        add(@uri, RDF::RDA.placeOfPublication, country)
      end
    end
    
    def parse_identifiers(identifiers)
      return unless identifiers.is_a?(Hash)
      identifiers.each_pair do |k,v|
        [*v].each do |val|
          next unless val
          case k
          when "librarything" then add(@uri, RDF::FOAF.isPrimaryTopicOf, RDF::URI.new("http://www.librarything.com/work/#{val}"))
          when "goodreads" then add(@uri, RDF::FOAF.isPrimaryTopicOf, RDF::URI.new("http://www.goodreads.com/book/show/#{val}"))
          end
        end
      end
    end

    def parse_oclc_numbers(oclc_nums)
      [*oclc_nums].each do |oclc_num|
        next if oclc_num.nil? or oclc_num.empty?
        [*oclc_num].each do |onum|
          next unless onum
          parse_oclc_number(onum)
        end
      end
    end

    def parse_volumes(vols)
      [*vols].each do | vol |
        next if !vol['key'] or vol['key'].empty?
        add(@uri, RDF::BIBO.volume, vol['key'])
      end
    end

    def parse_subjects(subjects)
      [*subjects].each do | subject |
        next if subject.nil? or subject.empty? or subject == "." or subject == " "
        if subject.is_a?(String)
          add(@uri, RDF::DC11.subject, subject)
          subject_string = subject.strip_trailing_punct
          subject_string.gsub!(/\s?--\s?/,"--")
          if subject_uri = DB.get(subject_string)
            puts subject_uri
            add(@uri, RDF::DC.subject, RDF::URI.new(subject_uri))
          end          
        elsif subject.is_a?(Hash) && subject['key'] && !(subject['key'].nil? || subject['key'].empty?)
          add(@uri, RDF::DC.subject, RDF::URI.new(URI_PREFIX+subject['key']))
          add(@uri, RDF::DC11.subject, subject['key'].split("/").last.gsub("_", " "))
        end
      end
    end
    
    alias :parse_subject_people :parse_subjects
    alias :parse_subject_times :parse_subjects
    alias :parse_subject_places :parse_subjects
    
    # Not subject_place since it seems like it's just pulling the subdivision from the subject heading

    def parse_ocaid(ocaid)
      return if ocaid.nil? or ocaid.empty? or !ocaid.strip.match(/^[A-z0-9]*$/) 
      add(@uri, RDF::DC11.identifier, ocaid.strip)
      #['pdf','epub','djvu','mobi'].each do |fmt|
      #  add(@uri, RDF::DC.hasFormat, RDF::URI.new("http://www.archive.org/download/#{data['ocaid'].strip}/#{data['ocaid'].strip}.#{fmt}")]
      #end
      #add(@uri, RDF::DC.hasFormat, RDF::URI.new("http://www.archive.org/download/#{data['ocaid'].strip}/#{data['ocaid'].strip}_djvu.txt")]
      add(@uri, RDF::FOAF.page, "http://www.archive.org/details/#{ocaid.strip}")
    end

    def parse_notes(notes)
      [*notes].each do |note|
        next unless note
        if note.is_a?(Hash)
          add(@uri, RDF::RDA.note, note['value']) unless note['value'].empty?
        elsif note.is_a?(Array)
          if note[0] == "value" && !note[1].empty?
            add(@uri, RDF::RDA.note, note[1])
          end
        elsif note.is_a?(String) && !note.empty?
          add(@uri, RDF::RDA.note, note)
        end
      end
    end
    
    def parse_oclc_number(oclc)
      [*oclc].each do |onum|
        next unless onum
        onum.gsub!(/[^\d]/,'')
        next if onum.empty?
        add(@uri, RDF::BIBO.oclcnum, onum)
        wc = RDF::URI.new("http://worldcat.org/oclc/#{onum}")
        add(@uri, RDF::FOAF.isPrimaryTopicOf, wc)
      end    
    end

    def parse_works(works)
      [*works].each do |work|
        next if work.nil? or work.empty?
        w = RDF::URI.new(URI_PREFIX+work['key'])
        add(@uri, RDF::DC.isVersionOf, w)
        add(@uri, RDF::OV.commonManifestation, w)
        add(w, RDF::DC.hasVersion, @uri)
        add(w, RDF::OV.commonManifestation, @uri)
      end
    end

    def parse_covers(covers)
      [*covers].each do |cover|
        next if cover.nil?
        ["S","M","L"].each do |size|
          add(@uri, RDF::FOAF.depiction, RDF::URI.new("http://covers.openlibrary.org/b/id/#{cover}-#{size}.jpg"))
        end
      end
    end  
  end  
end