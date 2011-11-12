# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{bugzyrb}
  s.version = Bugzyrb::Version::STRING

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = [%q{Rahul Kumar}]
  s.date = %q{2011-10-06}
  s.description = %q{basic, easy-to-use command-line issue-tracker using sqlite for ruby 1.9}
  s.email = %q{sentinel1879@gmail.com}
  s.executables = [%q{bugzyrb}]
  s.extra_rdoc_files = [
    "LICENSE",
    "README.rdoc"
  ]
  s.files = [
    ".document",
    "CHANGELOG.rdoc",
    "LICENSE",
    "NOTES",
    "README.rdoc",
    "Rakefile",
    "bin/bugzyrb",
    "bugzy.cfg",
    "bugzyrb.gemspec",
    "lib/bugzyrb.rb",
    "lib/bugzyrb/common/cmdapp.rb",
    "lib/bugzyrb/common/colorconstants.rb",
    "lib/bugzyrb/common/db.rb",
    "lib/bugzyrb/common/sed.rb"
  ]
  s.homepage = %q{http://github.com/rkumar/bugzyrb}
  s.require_paths = [%q{lib}]
  s.rubyforge_project = %q{bugzyrb}
  s.rubygems_version = %q{1.8.8}
  s.summary = %q{command-line bug/issue tracker using sqlite, ruby 1.9}

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<yard>, [">= 0.5"])
      s.add_runtime_dependency(%q<subcommand>, [">= 1.0.5"])
      s.add_runtime_dependency(%q<highline>, [">= 1.5.2"])
      s.add_runtime_dependency(%q<terminal-table>, [">= 1.4.2"])
      s.add_runtime_dependency(%q<sqlite3-ruby>, [">= 1.2.5"])
    else
      s.add_dependency(%q<yard>, [">= 0.5"])
      s.add_dependency(%q<subcommand>, [">= 1.0.5"])
      s.add_dependency(%q<highline>, [">= 1.5.2"])
      s.add_dependency(%q<terminal-table>, [">= 1.4.2"])
      s.add_dependency(%q<sqlite3-ruby>, [">= 1.2.5"])
    end
  else
    s.add_dependency(%q<yard>, [">= 0.5"])
    s.add_dependency(%q<subcommand>, [">= 1.0.5"])
    s.add_dependency(%q<highline>, [">= 1.5.2"])
    s.add_dependency(%q<terminal-table>, [">= 1.4.2"])
    s.add_dependency(%q<sqlite3-ruby>, [">= 1.2.5"])
  end
end

