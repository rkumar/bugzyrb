#!/usr/bin/env ruby 
=begin
  * Name:          bugzyrb.rb
  * Description:   a command line bug tracker uses sqlite3 (port of bugzy.sh)
  * Author:        rkumar
  * Date:          2010-06-24
  * License:       Ruby License

=end
require 'rubygems'
$:.unshift File.expand_path(File.dirname(__FILE__) + '/../lib')
require 'bugzyrb/common/colorconstants'
require 'bugzyrb/common/sed'
require 'bugzyrb/common/cmdapp'
require 'subcommand'
require 'sqlite3'
require 'highline/import'
require 'bugzyrb/common/db'
include ColorConstants
include Sed
include Cmdapp
include Subcommands
include Database

#PRI_A = YELLOW + BOLD
#PRI_B = WHITE  + BOLD
#PRI_C = GREEN  + BOLD
#PRI_D = CYAN  + BOLD
VERSION = "0.2.0"
DATE = "2010-07-24"
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
  #     $ alias bu='bugzyrb'
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
    @valid_type = %w[bug enhancement feature task] 
    @valid_severity = %w[normal critical moderate] 
    @valid_status = %w[open started closed stopped canceled] 
    @valid_priority = %w[P1 P2 P3 P4 P5] 
    $prompt_desc = $prompt_type = $prompt_status = $prompt_severity = $prompt_assigned_to = true
    $default_priority = nil
    $default_type = "bug"
    $default_severity = "normal"
    $default_status = "open"
    $default_priority = "P3"
    $default_assigned_to = "unassigned"
    $default_due = 5 # how many days in advance due date should be
    #$bare = @options[:bare]
      $use_readline = true
    $g_row = nil
    # we need to load the cfg file here, if given # , or else in home dir.
    if @options[:config]
      load @options[:config]
    end
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
  # schema  - adding created_by for bug and comment and log, but how to get ?
  #           assuming created by will contain email id so longish.
  def init args=nil
      die "#{@file} already exist. Please delete if you wish to recreate." if File.exists? @file

      @db = SQLite3::Database.new( @file )
      sql = <<SQL

      CREATE TABLE bugs (
        id INTEGER PRIMARY KEY,
        status VARCHAR(10) NOT NULL,
        severity VARCHAR(10),
        type VARCHAR(10),
        assigned_to VARCHAR(10),
        start_date DATE default CURRENT_DATE,
        due_date DATE,
        comment_count INTEGER default 0,
        priority VARCHAR(10),
        title VARCHAR(10) NOT NULL,
        description TEXT,
        fix TEXT,
        created_by VARCHAR(60),
        project VARCHAR(10),
        component VARCHAR(10),
        version VARCHAR(10),
        date_created  DATETIME default CURRENT_TIMESTAMP,
        date_modified DATETIME default CURRENT_TIMESTAMP);

      CREATE TABLE comments (
        rowid INTEGER PRIMARY KEY,
        id INTEGER NOT NULL ,
        comment TEXT NOT NULL,
        created_by VARCHAR(60),
        date_created DATETIME default CURRENT_TIMESTAMP);

      CREATE TABLE log (
        rowid INTEGER PRIMARY KEY,
        id INTEGER ,
        field VARCHAR(15),
        log TEXT,
        created_by VARCHAR(60),
        date_created DATETIME default CURRENT_TIMESTAMP);
     
SQL

      ret = @db.execute_batch( sql )
      # execute batch only returns nil
      message "#{@file} created." if File.exists? @file
      text = <<-TEXT
      If you wish to associate projects and/or components and versions to an issue,
      please modify bugzyrb.cfg as follows:

      $use_project = true
      $use_component = true
      $use_version = true
      Also, fill in valid_project=[...], default_project="x" and prompt_project=true.

      bugzyrb.cfg must be called using -c bugzyrb.cfg if overriding ~/.bugzyrb.cfg

      TEXT
      message text

      0
  end
  def get_db
    @db ||= DB.new @file
  end
  # returns default due date for add or qadd
  # @return [Date] due date 
  def default_due_date
    #Date.parse(future_date($default_due).to_s[0..10]) # => converts to a Date object
    Date.today + $default_due
  end
  ##
  # quick add which does not prompt user at all, only title is required on commandline
  # all other fields will go in as defaults
  # One may override defaults by specifying options
  def qadd args
    die "Title required by qadd" if args.nil? or args.empty?
    db = get_db
    body = {}
    body['title'] = args.join " "
    body['type']        = @options[:type]     || $default_type 
    body['severity']    = @options[:severity] || $default_severity
    body['status']      = @options[:status]   || $default_status
    body['priority']    = @options[:priority] || $default_priority
    body['assigned_to']    = @options[:assigned_to] || $default_assigned_to
    #comment_count = 0
    #body['description = nil
    #fix = nil
    body['start_date']  = @now
    body['due_date']    = default_due_date
    rowid = db.table_insert_hash("bugs", body)
    puts "Issue #{rowid} created"
    type = body['type']
    title = body['title']
    logid = db.sql_logs_insert rowid, "create", "#{rowid} #{type}: #{title}"
    body["id"] = rowid
    mail_issue nil, body
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
    title = text
    desc = nil
    if $prompt_desc
      message "Enter a detailed description (. to exit): "
      desc = get_lines
      #message "You entered #{desc}"
    end
    type = $default_type || "bug"
    severity = $default_severity || "normal"
    status = $default_status || "open"
    priority = $default_priority || "P3"
    if $prompt_type
      type = _choice("Select type:", %w[bug enhancement feature task] )
      #message "You selected #{type}"
    end
    if $prompt_severity
      severity = _choice("Select severity:", %w[normal critical moderate] )
      #message "You selected #{severity}"
    end
    if $prompt_status
      status = _choice("Select status:", %w[open started closed stopped canceled] )
      #message "You selected #{status}"
    end
    assigned_to = $default_assigned_to
    if $prompt_assigned_to
      message "Assign to:"
      #assigned_to = $stdin.gets.chomp
      assigned_to = _gets "assigned_to", "assigned_to", $default_assigned_to
      #message "You selected #{assigned_to}"
    end
    project = component = version = nil
    # project
    if $use_project
      project = user_input('project', $prompt_project, nil, $valid_project, $default_project)
    end
    if $use_component
      component = user_input('component', $prompt_component, nil, $valid_component, $default_component)
    end
    if $use_version
      version = user_input('version', $prompt_version, nil, $valid_version, $default_version)
    end

    start_date = @now
    due_date = default_due_date
    comment_count = 0
    priority ||= "P3" 
    description = desc
    fix = nil #"Some long text" 
    #date_created = @now
    #date_modified = @now
    body = {}
    body["title"]=title
    body["description"]=description
    body["type"]=type
    body["status"]=status
    body["start_date"]=start_date.to_s
    body["due_date"]=due_date.to_s
    body["priority"]=priority
    body["severity"]=severity
    body["assigned_to"]=assigned_to
    body["created_by"] = $default_user
    # only insert if its wanted by user
    body["project"]=project if $use_project
    body["component"]=component if $use_component
    body["version"]=version if $use_version

    rowid = db.table_insert_hash("bugs", body)
    puts "Issue #{rowid} created"
    logid = db.sql_logs_insert rowid, "create", "#{rowid} #{type}: #{title}"
    body["id"] = rowid
    mail_issue nil, body
    
    0
  end
  def mail_issue subject, row, emailid=nil
    emailid ||= $default_user
    body = <<TEXT
    Id            : #{row['id']} 
    Title         : #{row['title']} 
    Description   : #{row['description']} 
    Type          : #{row['type']} 
    Status        : #{row['status']} 
    Start Date    : #{row['start_date']} 
    Due Date      : #{row['due_date']} 
    Priority      : #{row['priority']} 
    Severity      : #{row['severity']} 
    Assigned To   : #{row['assigned_to']} 
TEXT
    body << "    Project       : #{row['project']}\n" if $use_project
    body << "    Component     : #{row['component']}\n" if $use_component
    body << "    Version       : #{row['version']}\n" if $use_version
    subject ||= "#{row['id']}: #{row['title']} "

    cmd = %{ mail -s "#{subject}" "#{emailid}" }
    #puts cmd
    Cmdapp::pipe_output(cmd, body)
  end

  ##
  # view details of a single issue/bug
  # @param [Array] ARGV, first element is issue number
  #                If no arg supplied then shows highest entry
  def view args
    db = get_db
    id = args[0].nil? ? db.max_bug_id : args[0]
    db, row = validate_id id
    die "No data found for #{id}" unless row
    puts "[#{row['type']} \##{row['id']}] #{row['title']}"
    puts row['description']
    puts 
    comment_count = 0
    #puts row
    row.each_pair { |name, val| 
      next if name == "project" && !$use_project
      next if name == "version" && !$use_version
      next if name == "component" && !$use_component
      comment_count = val.to_i if name == "comment_count"
      n = sprintf("%-15s", name); 
      puts "#{n} : #{val}" 
    }
    puts
    if comment_count > 0
      puts "Comments   :"
      db.select_where "comments", "id", id do |r|
        #puts r.join(" | ")
        puts "(#{r['date_created']}) [ #{r['created_by']} ] #{r['comment']}"
        #pp r
      end
    end
    puts "Log:"
    db.select_where "log", "id", id do |r|
      #puts r.join(" | ")
      puts "------- (#{r['date_created']}) ------"
      puts "#{r['field']} [ #{r['created_by']} ] #{r['log']} "
      #pp r
    end
  end
  ## tried out a version of view that uses template replacement
  # but can't do placement of second column -- it does not come aligned, so forget
  # NOTE: use rdoc/template instead - can handle arrays
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
    editable << "project" if $use_project
    editable << "component" if $use_component
    editable << "version" if $use_version
    sel = _choice "Select field to edit", editable
    print "You chose: #{sel}"
    old =  row[sel]
    puts " Current value is: #{old}"
    $g_row = row
    meth = "ask_#{sel}".to_sym
    if respond_to? "ask_#{sel}".to_sym
      str = send(meth, old)
    else
      #print "Enter value: "
      #str = $stdin.gets.chomp
      str = _gets sel, sel, old
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
    str = str.to_s
    rowid = db.sql_logs_insert id, sel, "[#{id}] updated [#{sel}] with #{str[0..50]}"
    0
  end
  # deletes given issue
  # @param [Array] id of issue
  # @example
  # bu delete 1
  # bu $0 delete 2 3 4
  # bu $0 delete $(jot - 6 10)
  def delete args
    #id = args.shift
    ctr = 0
    args.each do |id| 
      if @options[:force]
        db, row = validate_id id, false
        db.sql_delete_bug id
        ctr += 1
      else
        db, row = validate_id id, true
        if agree("Delete issue #{id}?  ")
          db.sql_delete_bug id
          ctr += 1
        else
          message "Operation cancelled"
        end
      end
    end
    message "#{ctr} issue/s deleted"
    0
  end
  def copy args
    id = args.shift
    db, row = validate_id id, true
    newrow = row.to_hash
    ret = newrow.delete("id")
    newrow.delete("date_created")
    newrow.delete("date_modified")
    #row.each_pair { |name, val| puts "(#{name}): #{val} " }
    ret = ask_title row['title']
    newrow['title'] = ret.chomp if ret
    rowid = db.table_insert_hash( "bugs", newrow)

    title = newrow['title']
    type = newrow['type']

    logid = db.sql_logs_insert rowid, "create", "#{rowid} #{type}: #{title}"
    newrow["id"] = rowid
    mail_issue nil, newrow
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
    incl, excl = Cmdapp._list_args args
    db = get_db
    #db.run "select * from bugs " do |row|
    #end
    fields = "id,status,title,severity,priority,start_date,due_date"
    if @options[:short]
      fields = "id,status,title"
    elsif @options[:long]
      fields = "id,status,title,severity,priority,due_date,description"
    end
    where = nil
    wherestring = ""
    if @options[:overdue]
      #where =  %{ where status != 'closed' and due_date <= "#{Date.today}" }
      where ||= []
      where <<  %{ status != 'closed'} 
      where <<  %{ due_date <= "#{Date.today}" }
    end
    if @options[:unassigned]
      #where =  %{ where status != 'closed' and due_date <= "#{Date.today}" }
      where ||= []
      where <<  %{ (assigned_to = 'unassigned' or assigned_to is null) } 
    end
    if where
      wherestring = " where " + where.join(" and ")
    end
    puts wherestring

    rows = db.run "select #{fields} from bugs #{wherestring} "
    die "No rows" unless rows

    rows = Cmdapp.filter_rows( rows, incl) do |row, regexp|
      row['title'] =~ regexp
    end
    rows = Cmdapp.filter_rows( rows, excl) do |row, regexp|
      row['title'] !~ regexp
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
    type = _choice("Select type:", %w[bug enhancement feature task] )
  end
  def ask_severity old=nil
    severity = _choice("Select severity:", %w[normal critical moderate] )
  end
  def ask_status old=nil
    status = _choice("Select status:", %w[open started closed stopped canceled] )
  end
  def ask_priority old=nil
    priority = _choice("Select priority:", %w[P1 P2 P3 P4 P5] )
  end
  def ask_fix old=nil
    Cmdapp::edit_text old
  end
  def ask_description old=nil
    Cmdapp::edit_text old
  end
  def ask_title old=nil
    ret = Cmdapp::edit_text old
    return ret.chomp if ret
    ret
  end
  ##
  # prompts user for a cooment to be attached to a issue/bug
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
  # insert comment into database
  # called from interactive, as well as "close" or others
  # Should we send a mail here ? XXX
  def _comment db, id, text
    rowid = db.sql_comments_insert id, text
    puts "Comment #{rowid} created"
    handle = db.db
    
    commcount = handle.get_first_value( "select count(id) from comments where id = #{id};" )
    commcount = commcount.to_i
    db.sql_update "bugs", id, "comment_count", commcount
    rowid = db.sql_logs_insert id, "comment",text[0..50]
  end
  # prompts user for a fix related to an issue
  def fix args #id, fix
    id = args.shift
    unless id
      id = ask("Issue Id?  ", Integer)
    end
    db, row = validate_id id
    if !args.empty?
      text = args.join(" ")
    else
      # XXX give the choice of using vim
      message "Enter a fix (. to exit): "
      text = get_lines
    end
    die "Operation cancelled" if text.nil? or text.empty?
    message "fix is: #{text}."
    message "Adding fix to #{id}: #{row['title']}"
    _fix db, id, text
    0
  end
  # internal method that actually updates the fix. can be called
  # from fix or from close using --fix
  # Should we send a mail here ? XXX
  def _fix db, id, text
    db.sql_update "bugs", id, "fix", text
    rowid = db.sql_logs_insert id, "fix", text[0..50]
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
      # try to find out values
      #vfield = "@valid_#{field}"
      #valid = eval(vfield).join(",")
      #die "#{value} is not valid for #{field} (#{valid})" unless bool
      return 1 unless bool
    end
    args.each do |id| 
      db, row = validate_id id
      curr_status = row[field]
      # don't update if already closed
      if curr_status != value
        db.sql_update "bugs", id, field, value
        puts "Updated #{id}"
        rowid = db.sql_logs_insert id, field, "[#{id}] updated [#{field}] with #{value}"
        row[field] = value
        mail_issue "[#{id}] updated [#{field}] with #{value}", row
      else
        message "#{id} already #{value}"
      end
      _comment(db, id, @options[:comment]) if @options[:comment]
      _fix(db, id, @options[:fix]) if @options[:fix]
    end
    0
  end
  def status args
    value = args.shift
    ret = change_value "status", value, args
    if ret != 0
      die "#{value} is not valid for status. Valid are (#{@valid_status.join(',')})" 
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

  #def future_date days=1
    #Time.now() + (24 * 60 * 60 * days)
  #end

  # prompt user for due date, called from edit
  # NOTE: this takes a peek at $g_row to get start_date and validate against that
  def ask_due_date old=nil
    days = $default_due
    today = Date.today
    start = Date.parse($g_row['start_date'].to_s) || today
    ask("Enter due date? (>= #{start}) ", Date) { 
      |q| q.default = (today + days).to_s;
      q.validate = lambda { |p| Date.parse(p) >= start }; 
      q.responses[:not_valid] = "Enter a date >= than #{start}"
    }
  end

  def ask_start_date old=nil
    ask("Enter start date?  ", Date) { 
      #|q| q.default = Time.now.to_s[0..10]; 
      |q| q.default = Date.today
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

  # get choice from user from a list of options
  # @param [String] prompt text
  # @param [Array] values to chose from
  # FIXME: move to Cmdapp
  def _choice prompt, choices
    choose do |menu|
      menu.prompt = prompt
      menu.choices(*choices) do |n|  return n; end
    end
  end
  #
  # take user input based on value of flag 
  # @param [String] column name
  # @param [Boolean, Symbol] true, false, :freeform, :choice
  # @param [String, nil] text to prompt
  # @param [Array, nil] choices array or nil
  # @param [Object] default value
  # @return [String, nil] users choice
  #
  # TODO: should we not check for the ask_x methods and call them if present.
  # FIXME: move to Cmdapp
  def user_input column, prompt_flag, prompt_text=nil, choices=nil, default=nil
    if prompt_flag == true
      prompt_flag = :freeform
      prompt_flag = :choice if choices
    end
    case prompt_flag
    when :freeform
      prompt_text ||= "#{column.capitalize}"
      #str = ask(prompt_text){ |q| q.default = default if default  }
      str = _gets(column, prompt_text, default)
      return str
    when :choice
      prompt_text ||= "Select #{column}:"
      str = _choice(prompt_text, choices)
      return str
    when :multiline, :ml
      return Cmdapp::edit_text default
    when false
      return default
    end
  end
  def test args=nil
    puts "This is only for testing things out"
    if $use_project
      project = user_input('project', $prompt_project, nil, $valid_project, $default_project)
      puts project
    end
    if $use_component
      component = user_input('component', $prompt_component, nil, $valid_component, $default_component)
      puts component
    end
  end
  ## prompts user for multiline input
  # NOTE: we do not take Ctrl-d as EOF then causes an error in next input in 1.9 (not 1.8)
  # @param [String] text to use as prompt
  # @return [String, nil] string with newlines or nil (if nothing entered).
  # FIXME: move to Cmdapp
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
    return str.chomp
  end
  # get a string from user, using readline or gets
  # if readline, then manage column specific history
  # FIXME: move to Cmdapp.
  def _gets column, prompt, default=nil
    text = "#{prompt}? "
    text << "|#{default}|" if default
    puts text
    if $use_readline
      Cmdapp::history_read column, default
      str = Readline::readline('>', false)
      Cmdapp::history_save column, str
      str = default if str.nil? or str == ""
      return str
    else
      str = $stdin.gets.chomp
      str = default if str.nil? or str == ""
      return str
    end
  end
  # ADD here

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
      config = File.expand_path "~/.bugzyrb.cfg"
      if File.exists? config
        options[:config] = config
        #puts "found  #{config} "
      end

  Subcommands::global_options do |opts|
    opts.banner = "Usage: #{APPNAME} [options] [subcommand [options]]"
    opts.description = "Todo list manager"
    #opts.separator ""
    #opts.separator "Global options are:"
    opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
      options[:verbose] = v
    end
    opts.on("-c", "--config FILENAME", "config filename path") do |v|
      v = File.expand_path v
      options[:config] = v
      if !File.exists? v
        die "#{RED}#{v}: no such file #{CLEAR}"
      end
    end
    opts.on("-d DIR", "--dir DIR", "Use bugs file in this directory") do |v|
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
    opts.description = "Add a bug/issue."
    opts.on("-f", "--[no-]force", "force verbosely") do |v|
      options[:force] = v
    end
    opts.on("-P", "--project PROJECTNAME", "name of project ") { |v|
      options[:project] = v
      #options[:filter] = true
    }
    opts.on("-p", "--priority PRI",  "priority code ") { |v|
      options[:priority] = v
    }
    opts.on("-C", "--component COMPONENT",  "component name ") { |v|
      options[:component] = v
    }
    opts.on("--severity SEV",  "severity code ") { |v|
      options[:severity] = v
    }
    opts.on("-t", "--type TYPE",  "type code ") { |v|
      options[:type] = v
    }
    opts.on("--status STATUS",  "status code ") { |v|
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
  Subcommands::command :copy do |opts|
    opts.banner = "Usage: copy [options] ISSUE_NO"
    opts.description = "Copy a given issue"
  end
  Subcommands::command :comment do |opts|
    opts.banner = "Usage: comment [options] ISSUE_NO TEXT"
    opts.description = "Add comment a given issue"
  end
  Subcommands::command :test do |opts|
    opts.banner = "Usage: test [options] ISSUE_NO TEXT"
    opts.description = "Add test a given issue"
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
    opts.on("-o","--overdue", "not closed, due date past") { |v|
      options[:overdue] = v
    }
    opts.on("-u","--unassigned", "not assigned") { |v|
      options[:unassigned] = v
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
  end
  Subcommands::command :status do |opts|
    opts.banner = "Usage: status [options] <STATUS> <ISSUE>"
    opts.description = "Change the status of an issue. \t<STATUS> are open closed started canceled stopped "
  end
  # TODO:
  #Subcommands::command :tag do |opts|
    #opts.banner = "Usage: tag <TAG> <TASKS>"
    #opts.description = "Add a tag to an item/s. "
  #end
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
