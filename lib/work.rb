module OpenLibrary
  class Work
    include OpenLibrary
    attr_reader :statements
    def initialize(data)
      @data = data
      set_identifier
      @statements = [RDF::Statement.new(@uri, RDF.type, RDF::FRBR.Work)]    
    end

    def parse_data
      @data.keys.each do |key|
        if self.respond_to?("parse_#{key}".to_sym)
          self.send("parse_#{key}".to_sym, @data[key])
        end
      end
    end

    def parse_title(t)
      unless t.empty?
        title = "#{t}"
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

    def parse_subjects(subjects)  

      [*subjects].each do | subject |
        next if subject.nil? or subject.empty? or subject == "."  or subject == " "
        if subject.is_a?(String)
          add(@uri, RDF::DC11.subject, subject)
          subject_string = subject.strip_trailing_punct
          subject_string.gsub!(/\s?--\s?/,"--")
          if subject_uri = DB.get(subject_string)
            add(@uri, RDF::DC.subject, RDF::URI.new(subject_uri))
          end               
        elsif subject.is_a?(Hash) && subject['key'] && !(subject['key'].nil? || subject['key'].empty?)
          add(@uri, RDF::DC.subject, RDF::URI.new(URI_PREFIX+subject['key']))
          add(@uri, RDF::DC11.subject, subject['key'].split("/").last.gsub("_", " "))
        end
      end

    end
    
    alias :parse_subject_places :parse_subjects
    alias :parse_subject_people :parse_subjects
    alias :parse_subject_times :parse_subjects

    def parse_first_publish_date(pub_date)
      return if pub_date.empty?
      add(@uri, RDF::DC.created, pub_date)
    end

    def parse_authors(auths) 
      authors = []
      [*auths].each do |au|
        next if !au['author'] or !au['author']['key'] or au['author']['key'].nil? or au['author']['key'].empty?
        a = RDF::URI.new(URI_PREFIX+au['author']['key'])
        add(@uri, RDF::DC.creator, a)
        add(a, RDF::FOAF.made, @uri)
        authors << a
        if DB.sismember "pending", au['author']['key']
          DB.append au['author']['key'], "||#{@uri.to_s}"
        elsif auth_list = DB.get(au['author']['key'])
          auth_list.split("||").each do |auth|
            add(@uri, RDF::OL.author, auth)
          end          
        else
          DB.set au['author']['key'], @uri.to_s
          DB.sadd "pending", au['author']['key']
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

    def parse_lc_classifications(lc_class)
      [*lc_class].each do |lcc|
        next if lcc.nil? or lcc.empty?
        lcc.gsub!(/\\/,' ')
        lcc.strip!
        lcc_node = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/lcc/#{CGI.escape(lcc)}#class")
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
    
    def parse_dewey_number(ddcs)
      [*ddcs].each do |ddc|
        next if ddc.nil? or ddc.empty?
        ddc_node = RDF::URI.new("http://api.talis.com/stores/openlibrary/items/ddc/#{CGI.escape(ddc)}#class")
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
       
    def parse_covers(covers)
      [*covers].each do |cover|
        next if cover.nil?
        ["S","M","L"].each do |size|
          add(@uri, RDF::FOAF.depiction, RDF::URI.new("http://covers.openlibrary.org/w/id/#{cover}-#{size}.jpg"))
        end
      end
    end  
  end
end