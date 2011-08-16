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