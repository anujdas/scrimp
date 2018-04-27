# -*- encoding: utf-8 -*-
require File.expand_path('../lib/scrimp/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Jacob Williams"]
  gem.email         = ["jacob.williams@cerner.com"]
  gem.description   = %q{Web UI for making requests to thrift services, given their IDL files.}
  gem.summary       = %q{Generic UI for thrift services.}
  gem.homepage      = "https://github.com/anujdas/scrimp"
  gem.licenses      = ['Apache-2.0']

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "scrimp"
  gem.require_paths = ["lib"]
  gem.version       = Scrimp::VERSION

  gem.add_runtime_dependency 'thrift', '~> 0.9'
  gem.add_runtime_dependency 'haml', '~> 4.0'
  gem.add_runtime_dependency 'sinatra', '~> 2.0'
end
