# SPDX-License-Identifier: MIT
# Run outside the source tree, with only the package closure on GEM_PATH.
require 'proiel'
require 'json'
require 'digest'

fixture = ARGV.fetch(0)
before = Digest::SHA256.file(fixture).hexdigest

def equal!(actual, expected, label)
  raise "#{label}: expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
end

equal!(PROIEL::VERSION, '1.3.3', 'upstream version')
File.open(fixture) do |io|
  xml = PROIEL::PROIELXML::Reader.parse_io(io).proiel
  equal!(xml.schema_version, '2.1', 'reader schema')
  equal!(xml.sources.map(&:id), ['guix-sample'], 'reader sources')
  equal!(xml.sources.first.divs.first.sentences.map(&:id), [100, 200], 'reader sentence IDs')
  equal!(xml.sources.first.divs.first.sentences.last.tokens.first.form, 'A&B', 'XML entity decoding')
end

treebank = PROIEL::Treebank.new.load_from_xml(fixture)
source = treebank.find_source('guix-sample')
validator = PROIEL::PROIELXML::Validator.new(fixture)
raise "schema/integrity validation failed: #{validator.errors.inspect}" unless validator.valid?

equal!([treebank.schema_version, source.language, source.title, source.license],
       ['2.1', 'lat', 'Guix synthetic treebank', 'MIT'], 'source metadata')
equal!(source.divs.map(&:id), [10], 'division IDs')
equal!(source.sentences.map { |sentence| [sentence.id, sentence.status, sentence.tokens.map(&:id)] },
       [[100, :reviewed, [101, 102]], [200, :annotated, [201, 202, 203]]], 'sentence/token structure')
equal!([treebank.find_sentence(100).annotated_by, treebank.find_sentence(100).reviewed_by],
       ['fixture', 'consumer'], 'annotation metadata')
equal!(source.tokens.map { |token| [token.id, token.form, token.lemma, token.part_of_speech,
                                   token.morphology, token.head_id, token.relation] },
       [[101, 'Luna', 'luna', 'Nb', '-s---fn--i', 102, 'sub'],
        [102, 'lucet', 'luceo', 'V-', '3spia----i', nil, 'pred'],
        [201, 'A&B', 'nomen', 'Nb', '-s---nn--i', 202, 'sub'],
        [202, 'videt', 'video', 'V-', '3spia----i', nil, 'pred'],
        [203, 'astrum', 'astrum', 'Nb', '-s---na--i', 202, 'obj']], 'parsed token attributes')
equal!(treebank.find_token(203).head.id, 202, 'dependency resolution')
equal!(treebank.find_token(202).dependents.map(&:id), [201, 203], 'dependency edges')
equal!(treebank.find_token(203).citation, 'Sample 2', 'citation assembly')
equal!(source.printable_form, 'Luna lucet. A&B videt astrum!', 'presentation reconstruction')
lexicon = PROIEL::Valency::Lexicon.new
lexicon.add_source!(source)
equal!(lexicon.lookup('video', 'V-'),
       [{ arguments: [{ relation: 'obj', case: 'a' }], tokens: { a: [202], r: [] } }], 'valency frame')
equal!(Digest::SHA256.file(fixture).hexdigest, before, 'read-only fixture')
puts JSON.generate(status: 'ok', version: PROIEL::VERSION, sources: 1, sentences: 2,
                   tokens: 5, dependency_edges: 3, fixture: File.basename(fixture))
