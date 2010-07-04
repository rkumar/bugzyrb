#!/usr/bin/env ruby -w
=begin
  * Name:          bugzyrb.rb
  * Description:   a command line bug tracker uses sqlite3 (port of bugzy.sh)
  * Author:        rkumar
  * Date:          2010-06-24
  * License:       Ruby License
  * Now requires subcommand gem

=end
require 'rubygems'
$:.unshift File.expand_path(File.dirname(__FILE__) + '/../lib')
require 'common/colorconstants'
require 'common/sed'
require 'common/cmdapp'
require 'subcommand'
require 'sqlite3'
require 'highline/import'
require 'common/db'
include ColorConstants
include Sed
include Cmdapp
include Subcommands
include Database

PRI_A = YELLOW + BOLD
PRI_B = WHITE  + BOLD
PRI_C = GREEN  + BOLD
PRI_D = CYAN  + BOLD
VERSION = "0.0.0"
DATE = "2010-06-24"
APPNAME = File.basename($0)
AUTHOR = "rkumar"

class Bugzy
  # This class is responsible for all todo task related functionality.
  #
  # == Create a file
  #
  #     $ bugzyrb init
  #
  # The above creates a bugzy.sqlite file
  #
  # Adding a task is the first operation.
  #     $ bugzyrb add "Create a project in rubyforge"
  #     $ bugzyrb add "Update Rakefile with project name"
  #
  # == List tasks
  # To list open/unstarted tasks:
  #     $ bugzyrb 
  # To list closed tasks also:
  #     $ bugzyrb --show-all
  #
  # If you are located elsewhere, give directory name:
  #     $ bugzyrb -d ~/
  #
  # == Close a task (mark as done)
  #     $ bugzyrb status close 1
  # 
  # == Add priority
  #     $ bugzyrb pri A 2
  #
  # For more:
  #     $ bugzyrb --help
  #     $ bugzyrb --show-actions
  #
  # == TODO:
  #
  def initialize options, argv
 
    @options = options
    @argv = argv
    @file = options[:file]
    ## data is a 2 dim array: rows and fields. It contains each row of the file
    # as an array of strings. The item number is space padded.
    @data = []
    init_vars
  end
  def init_vars
    @app_default_action = "list" # TODO:
    @file = @app_file_path = @options[:file] || "bugzy.sqlite"
    #@app_serial_path = File.expand_path("~/serial_numbers")
    @deleted_path = "todo_deleted.txt"
    @todo_delim = "\t"
    @appname = File.basename( Dir.getwd ) #+ ".#{$0}"
    # in order to support the testing framework
    t = Time.now
    #ut = ENV["TODO_TEST_TIME"]
    #t = Time.at(ut.to_i) if ut
    @now = t.strftime("%Y-%m-%d %H:%M:%S")
    @today = t.strftime("%Y-%m-%d")
    @verbose = @options[:verbose]
    # menu MENU
    # TODO: config
    # we need to read up from config file and update
    @valid_type = %w[bug enhancement feature task] 
    @valid_severity = %w[normal critical moderate] 
    @valid_status = %w[open started closed stopped canceled] 
    @valid_priority = %w[P1 P2 P3 P4 P5] 
    $default_type = "bug"
    $default_severity = "normal"
    $default_status = "open"
    $default_priority = "P3"
    $default_due = 5 # how many days in advance due date should be
    #$bare = @options[:bare]
  end
  %w[type severity status priority].each do |f| 
    eval(
    "def validate_#{f}(value)
      @valid_#{f}.include? value
    end"
        )
  end

  # initialize the database in current dir
  # should we add project and/or component ?
  def init args=nil
      die "#{@file} already exist. Please delete if you wish to recreate." if File.exists? @file

      @db = SQLite3::Database.new( @file )
      sql = <<SQL

      CREATE TABLE bugs (
        id INTEGER PRIMARY KEY,
        status VARCHAR(10),
        severity VARCHAR(10),
        type VARCHAR(10),
        assigned_to VARCHAR(10),
        start_date DATE default CURRENT_DATE,
        due_date DATE,
        comment_count INTEGER default 0,
        priority VARCHAR(10),
        title VARCHAR(10),
        description TEXT,
        fix TEXT,
        date_created  DATETIME default CURRENT_TIMESTAMP,
        date_modified DATETIME default CURRENT_TIMESTAMP);

      CREATE TABLE comments (
        rowid INTEGER PRIMARY KEY,
        id INTEGER NOT NULL ,
        comment TEXT NOT NULL,
        date_created DATETIME default CURRENT_TIMESTAMP);

      CREATE TABLE log (
        rowid INTEGER PRIMARY KEY,
        id INTEGER ,
        field VARCHAR(15),
        log TEXT,
        date_created DATETIME default CURRENT_TIMESTAMP);
     
SQL

      ret = @db.execute_batch( sql )
      # execute batch only returns nil
      message "#{@file} created." if File.exists? @file
      0
  end
  def get_db
    @db ||= DB.new @file
  end
  # returns default due date for add or qadd
  # @return [Date] due date 
  def default_due_date
    Date.parse(future_date($default_due).to_s[0..10]) # => converts to a Date object
  end
  ##
  # quick add which does not prompt user at all, only title is required on commandline
  # all other fields will go in as defaults
  # One may override defaults by specifying options
  def qadd args
    db = get_db
    title = args.join " "
    i_type        = @options[:type]     || $default_type 
    i_severity    = @options[:severity] || $default_severity
    i_status      = @options[:status]   || $default_status
    i_priority    = @options[:priority] || $default_priority
    i_assigned_to    = @options[:assigned_to] 
    comment_count = 0
    description = nil
    fix = nil
    start_date = @now
    due_date = default_due_date
    rowid = db.bugs_insert(i_status, i_severity, i_type, i_assigned_to, start_date, due_date, comment_count, i_priority, title, description, fix)
    puts "Issue #{rowid} created"
    rowid = db.sql_logs_insert rowid, "create", "#{rowid} #{i_type}: #{title}"
    0
  end

  ##
  # add an issue or bug
  # @params [Array] text of bug (ARGV), will be concatenated into single string
  # @return [0,1] success or fail
  # TODO: users should be able to switch on or off globals, and pass / change defaults
  # TODO: reading environ ENV and config file.
  def add args
    db = get_db
    if args.empty?
      print "Enter a short summary: "
      STDOUT.flush
      text = gets.chomp
      if text.empty?
        exit ERRCODE
      end
    else
      text = args.join " "
    end
    # convert actual newline to C-a. slash n's are escapes so echo -e does not muck up.
    #atitle=$( echo "$atitle" | tr -cd '\40-\176' )
    text.tr! "\n", ''
    $prompt_desc = $prompt_type = $prompt_status = $prompt_severity = $prompt_assigned_to = true
    $default_type = $default_severity = $default_status = nil
    $default_priority = nil
    i_title = text
    i_desc = nil
    if $prompt_desc
      message "Enter a detailed description (. to exit): "
      i_desc = get_lines
    end
    message "You entered #{i_desc}"
    i_type = $default_type || "bug"
    i_severity = $default_severity || "BUG"
    i_status = $default_status || "OPEN"
    i_priority = $default_priority || "P3"
    if $prompt_type
      i_type = _choice("Select type:", %w[bug enhancement feature task] )
      message "You selected #{i_type}"
    end
    if $prompt_severity
      i_severity = _choice("Select severity:", %w[normal critical moderate] )
      message "You selected #{i_severity}"
    end
    if $prompt_status
      i_status = _choice("Select status:", %w[open started closed stopped canceled] )
      message "You selected #{i_status}"
    end
    if $prompt_assigned_to
      message "Assign to:"
      i_assigned_to = $stdin.gets.chomp
      message "You selected #{i_assigned_to}"
    end
    start_date = @now
    due_date = default_due_date
    comment_count = 0
    priority ||= "P3" 
    title = i_title
    description = i_desc
    fix = nil #"Some long text" 
    #date_created = @now
    #date_modified = @now
    rowid = db.bugs_insert(i_status, i_severity, i_type, i_assigned_to, start_date, due_date, comment_count, priority, title, description, fix)
    puts "Issue #{rowid} created"
    rowid = db.sql_logs_insert rowid, "create", "#{rowid} #{i_type}: #{title}"
    0
  end
  ##
  # view details of a single issue/bug
  # @param [Array] ARGV, first element is issue number
  #                If no arg supplied then shows highest entry
  def view2 args
    db = get_db
    id = args[0].nil? ? db.max_bug_id : args[0]
    db, row = validate_id id
    die "No data found for #{id}" unless row
    puts "[#{row['type']} \##{row['id']}] #{row['title']}"
    puts row['description']
    puts 
    #puts row
    row.each_pair { |name, val| n = sprintf("%-15s", name); puts "#{n} : #{val}" }
    puts "Comments:"
    db.select_where "comments", "id", id do |r|
      #puts r.join(" | ")
      puts "(#{r['date_created']}) #{r['comment']}"
      #pp r
    end
  end
  ## tried out a version of view that uses template replacement
  # but can't do placement of second column -- it does not come aligned, so forget
  def view2 args
    db = get_db
    id = args[0].nil? ? db.max_bug_id : args[0]
    db, row = validate_id id
    die "No data found for #{id}" unless row
    t =  File.dirname(__FILE__) + "/common/" + "bug.tmpl"
    template = File::read(t)
    puts Cmdapp::template_replace(template, row)
    #puts row
    #puts "Comments:"
    t =  File.dirname(__FILE__) + "/common/" + "comment.tmpl"
    template = File::read(t)
    db.select_where "comments", "id", id do |r|
      puts Cmdapp::template_replace(template, r)
      #puts r.join(" | ")
      #puts "(#{r['date_created']}) #{r['comment']}"
      #pp r
    end
  end
  def edit args
    db = get_db
    id = args[0].nil? ? db.max_bug_id : args[0]
    row = db.sql_select_rowid "bugs", id
    die "No data found for #{id}" unless row
    editable = %w[ status severity type assigned_to start_date due_date priority title description fix ]
    sel = _choice "Select field to edit", editable
    print "You chose: #{sel}"
    old =  row[sel]
    puts " Current value is: #{old}"
    meth = "ask_#{sel}".to_sym
    if respond_to? "ask_#{sel}".to_sym
      str = send(meth, old)
    else
      print "Enter value: "
      str = $stdin.gets.chomp
    end
    #str = old if str.nil? or str == ""
    if str.nil? or str == old
      message "Operation cancelled."
      exit 0
    end
    message "Updating:"
    message str
    db.sql_update "bugs", id, sel, str
    puts "Updated #{id}"
    rowid = db.sql_logs_insert id, sel, "[#{id}] updated [#{sel}] with #{str[0..50]}"
    0
  end
  def viewlogs args
    db = get_db
    id = args[0].nil? ? db.max_bug_id : args[0]
    row = db.sql_select_rowid "bugs", id
    die "No data found for #{id}" unless row
    puts "[#{row['type']} \##{row['id']}] #{row['title']}"
    puts row['description']
    puts 
    ctr = 0
    db.select_where "log", "id", id do |r|
      ctr += 1
      puts "(#{r['date_created']}) #{r['field']} \t #{r['log']}"
      #puts "(#{r['date_created']}) #{r['log']}"
    end
    message "No logs found" if ctr == 0
    0
  end
  ##
  # lists issues
  # @param [Array] argv: containing Strings containing matching or non-matching terms
  #     +term means title should include term
  #     -term means title should not include term
  # @example
  #   list +testing
  #   list testing
  #   list crash -windows
  #   list -- -linux
  def list args
    # lets look at args as search words
    incl = []
    excl = []
    args.each do |e| 
      if e[0] == '+'
        incl << e[1..-1]
      elsif  e[0] == '-'
        excl << e[1..-1]
      else
        incl << e
      end
    end
    incl = nil if incl.empty?
    excl = nil if excl.empty?
    db = get_db
    #db.run "select * from bugs " do |row|
    #end
    fields = "id,status,title,severity,priority,start_date,due_date"
    if @options[:short]
      fields = "id,status,title"
    elsif @options[:long]
      fields = "id,status,title,severity,priority,due_date,description"
    end
    rows = db.run "select #{fields} from bugs "

    if incl
      incl_str = incl.join "|"
      r = Regexp.new incl_str
      rows = rows.select { |row| row['title'] =~ r }
    end
    if excl
      excl_str = excl.join "|"
      r = Regexp.new excl_str
      rows = rows.select { |row| row['title'] !~ r }
    end
    headings = fields.split ","
    # if you want to filter output send a delimiter
    if $bare
      delim = @options[:delimiter] || "\t" 
      puts headings.join delim
      rows.each do |e| 
        d = e['description'] 
        e['description'] = d.gsub(/\n/," ") if d
        puts e.join delim
      end
    else
      # pretty output tabular format etc
      require 'terminal-table/import'
      #table = table(nil, *rows)
      table = table(headings, *rows)
      puts table
    end
  end
  ## validate user entered id
  # All methods should call this first.
  # @param [Fixnum] id (actually can be String) to validate
  # @return [Database, #execute] database handle
  # @return [ResultSet] (arrayfields) data of row retrieved
  # NOTE: exits (die) if no such row, so if calling in a loop ...
  def validate_id id, print_header=false
    db = get_db
    #id ||= db.max_bug_id # if none supplied get highest - should we do this.
    # no since the caller will not have id, will bomb later
    row = db.sql_select_rowid "bugs", id
    die "No data found for #{id}" unless row
    if print_header
      puts "[#{row['type']} \##{row['id']}] #{row['title']}"
      puts row['description']
      puts 
    end
    return db, row
  end
  def putxx *args
    puts "GOT:: #{args}"
  end
  def ask_type old=nil
    i_type = _choice("Select type:", %w[bug enhancement feature task] )
  end
  def ask_severity old=nil
    i_severity = _choice("Select severity:", %w[normal critical moderate] )
  end
  def ask_status old=nil
    i_status = _choice("Select status:", %w[open started closed stopped canceled] )
  end
  def ask_priority old=nil
    i_priority = _choice("Select priority:", %w[P1 P2 P3 P4 P5] )
  end
  def ask_fix old=nil
    Cmdapp::edit_text old
  end
  def ask_description old=nil
    Cmdapp::edit_text old
  end
  def comment args #id, comment
    id = args.shift
    unless id
      id = ask("Issue Id?  ", Integer)
    end
    if !args.empty?
      comment = args.join(" ")
    else
      message "Enter a comment (. to exit): "
      comment = get_lines
    end
    die "Operation cancelled" if comment.nil? or comment.empty?
    message "Comment is: #{comment}."
    db, row = validate_id id
    die "No issue found for #{id}" unless row
    message "Adding comment to #{id}: #{row['title']}"
    _comment db, id, comment
    0
  end
  def _comment db, id, text
    rowid = db.sql_comments_insert id, text
    puts "Comment #{rowid} created"
    rowid = db.sql_logs_insert id, "comment",text[0..50]
  end
  def fix args #id, fix
    id = args.shift
    unless id
      id = ask("Issue Id?  ", Integer)
    end
    if !args.empty?
      text = args.join(" ")
    else
      message "Enter a fix (. to exit): "
      text = get_lines
    end
    die "Operation cancelled" if text.nil? or text.empty?
    message "fix is: #{text}."
    db, row = validate_id id
    message "Adding fix to #{id}: #{row['title']}"
    _fix db, id, text
    0
  end
  def _fix db, id, text
    db.sql_update "bugs", id, "fix", text
    rowid = db.sql_logs_insert id, "fix", text[0..50]
  end
  ## internal method to log an action
  # @param [Fixnum] id
  # @param [String] column or create/delete for row
  # @param [String] details such as content added, or content changed
  def log id, field, text
    id = args.shift
    unless id
      id = ask("Issue Id?  ", Integer)
    end
    if !args.empty?
      comment = args.join(" ")
    else
      message "Enter a comment (. to exit): "
      comment = get_lines
    end
    die "Operation cancelled" if comment.nil? or comment.empty?
    message "Comment is: #{comment}."
    db = get_db
    row = db.sql_select_rowid "bugs", id
    die "No issue found for #{id}" unless row
    message "Adding comment to #{id}: #{row['title']}"
    rowid = db.sql_logs_insert id, field, log
    puts "Comment #{rowid} created"
    0
  end

  ##
  # change value of given column 
  # This is typically called internally so the new value will be validated.
  # We can also do a validation against an array
  # @param [String] column name
  # @param [String] new value
  # @param [Array] array of id's to close (argv)
  # @return [0] for success
  def change_value field="status", value="closed", args
    #field = "status"
    #value = "closed"
    meth = "validate_#{field}".to_sym
    if respond_to? meth
      #bool = send("validate_#{field}".to_sym, value)
      bool = send(meth, value)
      die "#{value} is not valid for #{field}" unless bool
    end
    args.each do |id| 
      db, row = validate_id id
      curr_status = row[field]
      # don't update if already closed
      if curr_status != value
        db.sql_update "bugs", id, field, value
        puts "Updated #{id}"
        rowid = db.sql_logs_insert id, field, "[#{id}] updated [#{field}] with #{value}"
      else
        message "#{id} already #{value}"
      end
      _comment(db, id, @options[:comment]) if @options[:comment]
      _fix(db, id, @options[:fix]) if @options[:fix]
    end
    0
  end
  # close an issue (changes status of issue/s)
  # @param [Array] array of id's to close (argv)
  # @return [0] for success
  def close args
    change_value "status", "closed", args
    0
  end

  # start an issue (changes status of issue/s)
  # @param [Array] array of id's to start (argv)
  # @return [0] for success
  def start args
    change_value "status", "started", args
    0
  end

  ##
  # get a date in the future giving how many days
  # @param [Fixnum] how many days in the future
  # @return [Time] Date object in future
  # @example 
  #   future_date(1).to_s[0..10];  #  => creates a string object with only Date part, no time
  #   Date.parse(future_date(1).to_s[0..10]) # => converts to a Date object

  def future_date days=1
    Time.now() + (24 * 60 * 60 * days)
    #(Time.now() + (24 * 60 * 60) * days).to_s[0..10]; 
  end

  # prompt user for due date, called from edit
  def ask_due_date
    days = 1
    ask("Enter due date?  ", Date) { 
      |q| q.default = future_date(days).to_s[0..10]; 
      q.validate = lambda { |p| Date.parse(p) >= Date.parse(Time.now.to_s) }; 
      q.responses[:not_valid] = "Enter a date greater than today" 
    }
  end

  def ask_start_date
    ask("Enter start date?  ", Date) { 
      |q| q.default = Time.now.to_s[0..10]; 
    }
  end

  def check_file filename=@app_file_path
    File.exists?(filename) or die "#{filename} does not exist in this dir. Use 'add' to create an item first."
  end
  ##
  # colorize each line, if required.
  # However, we should put the colors in some Map, so it can be changed at configuration level.
  #
  def colorize # TODO:
    colorme = @options[:colorize]
    @data.each do |r| 
      if @options[:hide_numbering]
        string = "#{r[1]} "
      else
        string = " #{r[0]} #{r[1]} "
      end
      if colorme
        m=string.match(/\(([A-Z])\)/)
        if m 
          case m[1]
          when "A", "B", "C", "D"
            pri = self.class.const_get("PRI_#{m[1]}")
            #string = "#{YELLOW}#{BOLD}#{string}#{CLEAR}"
            string = "#{pri}#{string}#{CLEAR}"
          else
            string = "#{NORMAL}#{GREEN}#{string}#{CLEAR}"
            #string = "#{BLUE}\e[6m#{string}#{CLEAR}"
            #string = "#{BLUE}#{string}#{CLEAR}"
          end 
        else
          #string = "#{NORMAL}#{string}#{CLEAR}"
          # no need to put clear, let it be au natural
        end
      end # colorme
      ## since we've added notes, we convert C-a to newline with spaces
      # so it prints in next line with some neat indentation.
      string.gsub!('', "\n        ")
      #string.tr! '', "\n"
      puts string
    end
  end
  # internal method for sorting on reverse of line (status, priority)
  def sort # TODO:
    fold_subtasks
    if @options[:reverse]
      @data.sort! { |a,b| a[1] <=> b[1] }
    else
      @data.sort! { |a,b| b[1] <=> a[1] }
    end
    unfold_subtasks
  end
  def grep # TODO:
    r = Regexp.new @options[:grep]
    #@data = @data.grep r
    @data = @data.find_all {|i| i[1] =~ r }
  end

  ##
  # separates args into tag or subcommand and items
  # This allows user to pass e.g. a priority first and then item list
  # or item list first and then priority. 
  # This can only be used if the tag or pri or status is non-numeric and the item is numeric.
  def _separate args, pattern=nil #/^[a-zA-Z]/ 
    tag = nil
    items = []
    args.each do |arg| 
      if arg =~ /^[0-9\.]+$/
        items << arg
      else
        tag = arg
        if pattern
          die "#{@action}: #{arg} appears invalid." if arg !~ pattern
        end
      end
    end
    items = nil if items.empty?
    return tag, items
  end

  def _choice prompt, choices
    choose do |menu|
      menu.prompt = prompt
      menu.choices(*choices) do |n|  return n; end
    end
  end
  ## prompts user for multiline input
  # @param [String] text to use as prompt
  # @return [String, nil] string with newlines or nil (if nothing entered).
  #
  def get_lines prompt=nil
    #prompt ||= "Enter multiple lines, to quit enter . on empty line"
    #message prompt
    str = ""
    while $stdin.gets                        # reads from STDIN
      if $_.chomp == "."
        break
      end
      str << $_
      #puts "Read: #{$_}"                   # writes to STDOUT
    end
    return nil if str == ""
    return str
  end

  def self.main args
    ret = nil
    begin
      # http://www.ruby-doc.org/stdlib/libdoc/optparse/rdoc/classes/OptionParser.html
      require 'optparse'
      options = {}
      options[:verbose] = false
      options[:colorize] = true
      $bare = false
      # adding some env variable pickups, so you don't have to keep passing.
      showall = ENV["TODO_SHOW_ALL"]
      if showall
        options[:show_all] = (showall == "0") ? false:true
      end
      plain = ENV["TODO_PLAIN"]
      if plain
        options[:colorize] = (plain == "0") ? false:true
      end

  Subcommands::global_options do |opts|
    opts.banner = "Usage: #{APPNAME} [options] [subcommand [options]]"
    opts.description = "Todo list manager"
    #opts.separator ""
    #opts.separator "Global options are:"
    opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
      options[:verbose] = v
    end
    opts.on("-f", "--file FILENAME", "CSV filename") do |v|
      options[:file] = v
    end
    opts.on("-d DIR", "--dir DIR", "Use TODO file in this directory") do |v|
      require 'FileUtils'
      dir = File.expand_path v
      if File.directory? dir
        options[:dir] = dir
        # changing dir is important so that serial_number file is the current one.
        FileUtils.cd dir
      else
        die "#{RED}#{v}: no such directory #{CLEAR}"
      end
    end
    opts.on("--show-actions", "show actions ") do |v|
      #todo = Bugzy.new(options, ARGV)
      #todo.help nil - not working now that we've moved to subcommand
      puts Subcommands::print_actions
      exit 0
    end

    opts.on("--version", "Show version") do
      version = Cmdapp::version_info || VERSION
      puts "#{APPNAME} version #{version}, #{DATE}"
      puts "by #{AUTHOR}. This software is under the GPL License."
      exit 0
    end
    # No argument, shows at tail.  This will print an options summary.
    # Try it and see!
    #opts.on("-h", "--help", "Show this message") do
      #puts opts
      #exit 0
    #end
  end
  Subcommands::add_help_option
  Subcommands::global_options do |opts|
        opts.separator ""
        opts.separator "Common Usage:"
        opts.separator <<TEXT
        #{APPNAME} add "Text ...."
        #{APPNAME} list
        #{APPNAME} start 1
        #{APPNAME} close 1 
TEXT
  end

  Subcommands::command :init do |opts|
    opts.banner = "Usage: init [options]"
    opts.description = "Create a datastore (sqlite3) for bugs/issues"
  end

  Subcommands::command :add, :a do |opts|
    opts.banner = "Usage: add [options] TEXT"
    opts.description = "Add a task."
    opts.on("-f", "--[no-]force", "force verbosely") do |v|
      options[:force] = v
    end
    opts.on("-P", "--project PROJECTNAME", "name of project for add or list") { |v|
      options[:project] = v
      options[:filter] = true
    }
    opts.on("-p", "--priority PRI",  "priority code for add") { |v|
      options[:priority] = v
    }
    opts.on("-C", "--component COMPONENT",  "component name for add or list") { |v|
      options[:component] = v
    }
    opts.on("--severity SEV",  "severity code for add") { |v|
      options[:severity] = v
    }
    opts.on("-t", "--type TYPE",  "type code for add") { |v|
      options[:type] = v
    }
    opts.on("--status STATUS",  "status code for add") { |v|
      options[:status] = v
    }
    opts.on("-a","--assigned-to assignee",  "assigned to whom ") { |v|
      options[:assigned_to] = v
    }
  end
  Subcommands::command :qadd, :a do |opts|
    opts.banner = "Usage: qadd [options] TITLE"
    opts.description = "Add an issue with no prompting"
    opts.on("-p", "--priority PRI",  "priority code for add") { |v|
      options[:priority] = v
    }
    opts.on("-C", "--component COMPONENT",  "component name for add or list") { |v|
      options[:component] = v
    }
    opts.on("--severity SEV",  "severity code for add") { |v|
      options[:severity] = v
    }
    opts.on("-t","--type TYPE",  "type code for add") { |v|
      options[:type] = v
    }
    opts.on("--status STATUS",  "status code for add") { |v|
      options[:status] = v
    }
    opts.on("-a","--assigned-to assignee",  "assigned to whom ") { |v|
      options[:assigned_to] = v
    }
  end
  Subcommands::command :view do |opts|
    opts.banner = "Usage: view [options] ISSUE_NO"
    opts.description = "View a given issue"
  end
  Subcommands::command :edit do |opts|
    opts.banner = "Usage: edit [options] ISSUE_NO"
    opts.description = "Edit a given issue"
  end
  Subcommands::command :comment do |opts|
    opts.banner = "Usage: comment [options] ISSUE_NO TEXT"
    opts.description = "Add comment a given issue"
  end
  Subcommands::command :list do |opts|
    opts.banner = "Usage: list [options] search options"
    opts.description = "list issues"
    opts.on("--short", "short listing") { |v|
      options[:short] = v
    }
    opts.on("--long", "long listing") { |v|
      options[:long] = v
    }
    opts.on("-d","--delimiter STR", "listing delimiter") { |v|
      options[:delimiter] = v
    }
    opts.on("-b","--bare", "unformatted listing, for filtering") { |v|
      options[:bare] = v
      $bare = true
    }
  end
  Subcommands::command :viewlogs do |opts|
    opts.banner = "Usage: viewlogs [options] ISSUE_NO"
    opts.description = "view logs for an issue"
  end
  # XXX order of these 2 matters !! reverse and see what happens
  Subcommands::command :close, :clo do |opts|
    opts.banner = "Usage: clo [options] <ISSUENO>"
    opts.description = "Close an issue/s with fix or comment if given"
    opts.on("-f", "--fix TEXT", "add a fix while closing") do |v|
      options[:fix] = v
    end
    opts.on("-c", "--comment TEXT", "add a comment while closing") do |v|
      options[:comment] = v
    end
  end
  Subcommands::command :start, :sta do |opts|
    opts.banner = "Usage: sta [options] <ISSUENO>"
    opts.description = "Mark as started an issue/s with comment if given"
    #opts.on("-f", "--fix TEXT", "add a fix while closing") do |v|
      #options[:fix] = v
    #end
    opts.on("-c", "--comment TEXT", "add a comment while closing") do |v|
      options[:comment] = v
    end
  end
  #Subcommands::command :depri do |opts|
    #opts.banner = "Usage: depri [options] <TASK/s>"
    #opts.description = "Remove priority of task. \n\t bugzyrb depri <TASK>"
    #opts.on("-f", "--[no-]force", "force verbosely") do |v|
      #options[:force] = v
    #end
  #end
  Subcommands::command :delete, :del do |opts|
    opts.banner = "Usage: delete [options] <TASK/s>"
    opts.description = "Delete a task. \n\t bugzyrb delete <TASK>"
    opts.on("-f", "--[no-]force", "force - don't prompt") do |v|
      options[:force] = v
    end
    #opts.on("--recursive", "operate on subtasks also") { |v|
      #options[:recursive] = v
    #}
  end
  Subcommands::command :status do |opts|
    opts.banner = "Usage: status [options] <STATUS> <TASKS>"
    opts.description = "Change the status of a task. \t<STATUS> are open closed started pending hold next"
    opts.on("--recursive", "operate on subtasks also") { |v|
      options[:recursive] = v
    }
  end
  Subcommands::command :tag do |opts|
    opts.banner = "Usage: tag <TAG> <TASKS>"
    opts.description = "Add a tag to an item/s. "
  end
  #Subcommands::alias_command :open , "status","open"
  #Subcommands::alias_command :close , "status","closed"
  cmd = Subcommands::opt_parse()
  args.unshift cmd if cmd

  if options[:verbose]
    p options
    print "ARGV: " 
    p args #ARGV 
  end
  #raise "-f FILENAME is mandatory" unless options[:file]

  c = Bugzy.new(options, args)
  ret = c.run
    ensure
    end
  return ret
  end # main
end # class Bugzy

if __FILE__ == $0
  exit Bugzy.main(ARGV) 
end
