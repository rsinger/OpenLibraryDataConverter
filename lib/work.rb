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