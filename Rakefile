require 'rubygems'
require 'rake'
require 'hoe'

LIB_DIR = File.expand_path(File.join(File.dirname(__FILE__), 'lib'))
$LOAD_PATH << LIB_DIR

require 'silhouette/version'

HOE = Hoe.new('silhouette', Silhouette::VERSION) do |p|
  p.developer('Aaron Patterson', 'aaronp@rubyforge.org')
  p.readme_file   = 'README.rdoc'
  p.history_file  = 'CHANGELOG.rdoc'
  p.extra_rdoc_files  = FileList['*.rdoc']
  p.clean_globs = [
    'lib/silhouette/*.{o,so,bundle,a,log,dll}',
  ]

  p.extra_dev_deps  << "rake-compiler"

  p.spec_extras = { :extensions => ["ext/silhouette/extconf.rb"] }
end

gem 'rake-compiler', '>= 0.4.1'
require "rake/extensiontask"

RET = Rake::ExtensionTask.new("silhouette", HOE.spec) do |ext|
  ext.lib_dir = "lib/silhouette"
end

Rake::Task[:test].prerequisites << :compile
