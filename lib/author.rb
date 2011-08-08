module OpenLibrary
  class Author
    attr_reader :statements, :name_strings
    def initialize(data)
      @data = data
      set_identifier
      @statements = [RDF::Statement.new(@uri, RDF.type, RDF::FOAF.Agent)]    
      @name_strings = []
    end
  
    def parse_data
      parse_names
      @data.keys.each do |key|
        if self.respond_to?("parse_#{key}".to_sym)
          self.send("parse_#{key}".to_sym)
        end
      end
      save
    end
  
    def parse_names
      if @data['personal_name'] && !@data['personal_name'].empty?
        add(@uri, RDF::FOAF.name, @data['personal_name'])
        @name_strings << @data['personal_name']
        if @data['name'] && !@data['name'].empty?
          add(@uri, RDF::SKOS.altLabel, @data['name'])
          @name_strings << @data['name']
        end
      elsif @data['name'] && !@data['name'].empty?
        add(@uri, RDF::FOAF.name, @data['name'])
        @name_strings << @data['name']
      end  
      if @data['alternate_names'] && !@data['alternate_names'].empty?
        [*@data['alternate_names']].each do |alt_name|
          next if alt_name.nil? or alt_name.empty?
          add(@uri, RDF::SKOS.altLabel, alt_name)
          @name_strings << alt_name
        end
      end 

      if @data['fuller_name'] && !@data['fuller_name'].empty?
        [*@data['fuller_name']].each do |fn|
          next if fn.nil? or fn.empty?
          add(@uri, RDF::RDAG2.fullerFormOfName, fn)
          @name_strings << fn
        end
      end           
    end
  
    def save
      if val = DB.getset(@data['key'], @name_strings.uniq.join("||"))
        if DB.sismember("pending", @data['key'])
          val.split("||").each do |creation|
            name_strings.each do |name|
              add(RDF::URI.intern(creation), RDF::OL.author, name)
            end
          end
          DB.srem "pending", @data['key']
        end
      end    
    end
  
    def self.gen_author_list(authors)
      rest = RDF.nil
      list_members = []
      authors.reverse.each do | au |
        n = RDF::Node.new
        list_members << [n,RDF.first,au]
        list_members << [n,RDF.rest,rest]
        rest = n
      end
      {rest=>list_members}
    end    
  

    def parse_birth_date  
      return if @data['birth_date'].empty?
      node = RDF::Node.new
      add(node, RDF.type, RDF::BIO.Birth)
      add(node, RDF::BIO.principal, @uri)
      add(@uri, RDF::BIO.event, node)
      add(node, RDF::DC.date, @data['birth_date'])
    end
  
    def parse_death_date
      return if @data['death_date'].empty?
      node = RDF::Node.new
      add(node, RDF.type, RDF::BIO.Death)
      add(node, RDF::BIO.principal, @uri)
      add(@uri, RDF::BIO.event, node)
      add(node, RDF::DC.date, @data['death_date'])
    end
    
    def parse_website
      return if @data['website'].empty?
      if url = Util.sanitize_url(@data['website'])
        begin
          hp = RDF::URI.intern(url)
          hp.normalize!
          u = URI.parse(hp.to_s)
          return if hp.relative?
          add(@uri, RDF::FOAF.homepage, hp)
        rescue
        end
      end

    end
    
    def parse_bio
      return if @data['bio'].empty?
      if @data['bio'].is_a?(String)
        add(@uri, RDF::BIO.olb, @data['bio'])
      elsif @data['bio'].is_a?(Hash) && @data['bio']['value'] && !@data['bio']['value'].empty?
        add(@uri, RDF::BIO.olb,@data['bio']['value'])
      end

    end
    
    def parse_title
      return if @data['title'].empty?
      add(@uri, RDF::RDAG2.titleOfThePerson, @data['title'])      
    end

    def parse_wikipedia
      return if @data['wikipedia'].empty?
      [*@data['wikipedia']].each do |wik|
        next if wik.nil? or wik.empty?
        next unless w = Util.sanitize_url(wik)
        begin
          wp = RDF::URI.intern(w)
          wp.normalize!
          u = URI.parse(wp.to_s)
          return if wp.relative?
          add(@uri, RDF::FOAF.isPrimaryTopicOf, wp)
          if wp.host =~ /wikipedia\.org/
            dbpedia = RDF::URI.intern(wp.to_s)
            dbpedia.host = "dbpedia.org"
            dbpedia.path.sub!(/\/wiki\//,"/resource/")
            add(@uri, RDF::OWL.sameAs, dbpedia)
          end
        rescue
        end
      end

    end
    
    def parse_photos
      return if @data['photos'].empty?
      [*@data['photos']].each do |photo|
        next if photo.nil?
        ["S","M","L"].each do |size|
          add(@uri, RDF::FOAF.depiction, RDF::URI.new("http://covers.openlibrary.org/a/id/#{photo}-#{size}.jpg"))
        end
      end

    end
    
    def parse_links
      return if @data['links'].empty?
      if @data['links'].is_a?(Array)
        @data['links'].each do |link|
          if link.is_a?(Hash)
            if link['url']
              add(@uri, RDF::FOAF.page, link['url'])
            end
          end
        end
      end
    end  
  end
end