module OpenLibrary
  class Subject
    include OpenLibrary
    attr_reader :statements
    def initialize(data)
      @data = data
      set_identifier
      @statements = [RDF::Statement.new(@uri, RDF.type, RDF::SKOS.Concept)]    
    end
    def parse_data
      @data.keys.each do |key|
        if self.respond_to?("parse_#{key}".to_sym)
          self.send("parse_#{key}".to_sym, @data[key])
        end
      end
    end

    def parse_name(name)  
      return if name.empty?
      add(@uri, RDF::SKOS.prefLabel, @data['name'])      
    end

    def parse_created(created)
      add(@uri, RDF::DC.created, DateTime.parse(created['value']))
    end
    def parse_last_modified(modified)
      add(@uri, RDF::DC.modified, DateTime.parse(modified['value']))
    end
  end
end