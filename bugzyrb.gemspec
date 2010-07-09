# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run the gemspec command
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{bugzyrb}
  s.version = "0.2.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Rahul Kumar"]
  s.date = %q{2010-07-09}
  s.default_executable = %q{bugzyrb}
  s.description = %q{basic, easy-to-use command-line issue-tracker using sqlite for ruby 1.9}
  s.email = %q{sentinel1879@gmail.com}
  s.executables = ["bugzyrb"]
  s.extra_rdoc_files = [
    "LICENSE",
     "README.rdoc"
  ]
  s.files = [
    ".document",
     ".gitignore",
     "CHANGELOG.rdoc",
     "LICENSE",
     "README.rdoc",
     "Rakefile",
     "VERSION",
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
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{bugzyrb}
  s.rubygems_version = %q{1.3.6}
  s.summary = %q{command-line bug/issue tracker using sqlite, ruby 1.9}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<yard>, [">= 0.5"])
      s.add_runtime_dependency(%q<subcommand>, [">= 1.0.5"])
      s.add_runtime_dependency(%q<highline>, [">= 1.5.2"])
      s.add_runtime_dependency(%q<terminal-table>, [">= 1.4.2"])
      s.add_runtime_dependency(%q<sqlite3-ruby>, [">= 1.2.5"])
      s.add_runtime_dependency(%q<arrayfields>, [">= 4.7.4"])
    else
      s.add_dependency(%q<yard>, [">= 0.5"])
      s.add_dependency(%q<subcommand>, [">= 1.0.5"])
      s.add_dependency(%q<highline>, [">= 1.5.2"])
      s.add_dependency(%q<terminal-table>, [">= 1.4.2"])
      s.add_dependency(%q<sqlite3-ruby>, [">= 1.2.5"])
      s.add_dependency(%q<arrayfields>, [">= 4.7.4"])
    end
  else
    s.add_dependency(%q<yard>, [">= 0.5"])
    s.add_dependency(%q<subcommand>, [">= 1.0.5"])
    s.add_dependency(%q<highline>, [">= 1.5.2"])
    s.add_dependency(%q<terminal-table>, [">= 1.4.2"])
    s.add_dependency(%q<sqlite3-ruby>, [">= 1.2.5"])
    s.add_dependency(%q<arrayfields>, [">= 4.7.4"])
  end
end

