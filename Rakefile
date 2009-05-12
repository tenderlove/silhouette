require 'rubygems'
require 'rake'
require 'rake/gempackagetask'

$VERBOSE = nil

spec = Gem::Specification.new do |s|
  s.name = 'silhouette'
  s.version = '2.0.0'
  s.summary = 'A 2 stage profiler'
  s.author = 'Evan Webb'
  s.email = 'evan@fallingsnow.net'

  s.has_rdoc = true
  s.files = File.read('Manifest.txt').split($/)
  s.require_path = 'lib'
  s.executables = ['silhouette', 'silhouette_coverage', 'silrun']
  s.default_executable = 'silhouette'
  s.extensions = ['extconf.rb']
end

desc 'Build Gem'
Rake::GemPackageTask.new spec do |pkg|
  pkg.need_tar = true
end

desc 'Clean up'
task :clean => [ :clobber_package ]

desc 'Clean up'
task :clobber => [ :clean ]

# vim: syntax=Ruby

