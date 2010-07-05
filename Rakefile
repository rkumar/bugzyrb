require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "bugzyrb"
    gem.summary = %Q{command-line bug/issue tracker using sqlite, ruby 1.9}
    gem.description = %Q{command-line issue tracker using sqlite for ruby 1.9}
    gem.email = "sentinel1879@gmail.com"
    gem.homepage = "http://github.com/rkumar/bugzyrb"
    gem.authors = ["Rahul Kumar"]
    gem.rubyforge_project = "bugzyrb"
    #gem.add_development_dependency "thoughtbot-shoulda", ">= 0"
    gem.add_development_dependency "yard", ">= 0.5"
    gem.add_dependency "subcommand", ">= 1.0.5"
    gem.add_dependency "highline", ">= 1.5.2"
    gem.add_dependency "terminal-table", ">= 1.4.2"
    gem.add_dependency "sqlite3-ruby", ">= 1.2.5"
    gem.add_dependency "arrayfields", ">= 4.7.4"
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |test|
    test.libs << 'test'
    test.pattern = 'test/**/test_*.rb'
    test.verbose = true
  end
rescue LoadError
  task :rcov do
    abort "RCov is not available. In order to run rcov, you must: sudo gem install spicycode-rcov"
  end
end

task :test => :check_dependencies

task :default => :test

begin
  require 'yard'
  YARD::Rake::YardocTask.new
rescue LoadError
  task :yardoc do
    abort "YARD is not available. In order to run yardoc, you must: sudo gem install yard"
  end
end
