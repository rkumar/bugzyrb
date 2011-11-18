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
require 'bugzyrb/version'
require 'subcommand'
require 'sqlite3'
require 'highline/import'
require 'bugzyrb/common/db'
include ColorConstants
include Sed
include Cmdapp
include Subcommands
include Database

# monkey_patch for terminal_table using coloring, does *not* work perfectly here
# https://gist.github.com/625808
ELIMINATE_ANSI_ESCAPE = true
class String
  alias_method :to_s_orig, :to_s
  def to_s
    str = self.to_s_orig
    if ::ELIMINATE_ANSI_ESCAPE
      str = str.sub(/^\e\[[\[\e0-9;m]+m/, "")
      str = str.sub(/(\e\[[\[\e0-9;m]+m)$/, "")
      # Above works for only one, beg or eol
      str = str.gsub(/\e\[[\[\e0-9;m]+m/, "")
      #str = str.gsub(/(\e\[[\[\e0-9;m]+m)/, "")
    end
    str
  end
end
# end monkey
#
VERSION = Bugzyrb::Version::STRING
DATE = "2011-09-30"
APPNAME = File.basename($0)
AUTHOR = "rkumar"

class Bugzy
  # This class is responsible for all bug task related functionality.
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
  # ==  tasks
  # To list open/unstarted tasks:
  #     $ bugzyrb 
  # To list closed tasks also:
  #     $ bugzyrb --show-all
  #
  # If you are located elsewhere, give directory name:
  #     $ bugzyrb -d ~/
  #
  # == Close a task (mark as done)
  #     $ bugzyrb close 1
  # 
  # == Change priority of items 4 and 6 to P2
  #     $ bugzyrb pri P2 4 6
  #
  # For more:
  #     $ bugzyrb --help
  #     $ bugzyrb --show-actions
  #     $ alias bu='bugzyrb'
  #
  # == TODO:
  #  -- archive completed tasks
  #  -- i cannot do any coloring with fields i have not selected. I need to get around this
  #   of having fields in select that are not displayed. Such as type/priority/date
  #  -- refactor and cleanup, its a mess. Should be able to configure coloring elsewhere.
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
    #@deleted_path = "todo_deleted.txt"
    #@todo_delim = "\t"
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
    $prompt_desc = $prompt_type = $prompt_status = $prompt_severity = $prompt_assigned_to = $prompt_priority = true
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
        priority VARCHAR(2),
        title VARCHAR(20) NOT NULL,
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
  # get a connection to the database, checking up 3 levels.
  def get_db
    # we want to check a couple levels 2011-09-28 
    unless @db
      unless File.exists? @file
        3.times do |i|
          @file = "../#{@file}"
          break if File.exists? @file
        end
      end
    end
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
      # if you add last arg as P1..P5, I'll update priority automatically
      if args.last =~ /P[1-5]/
        $default_priority = args.pop
      end
      text = args.join " "
    end
    # convert actual newline to C-a. slash n's are escapes so echo -e does not muck up.
    #atitle=$( echo "$atitle" | tr -cd '\40-\176' )
    text.tr! "\n", ''
    title = text
    desc = nil
    if $prompt_desc
      # choice of vim or this XXX also how to store in case of error or abandon
      # and allow user to edit, so no retyping. This could be for mult fields
      message "Enter a detailed description (. to exit): "
      desc = Cmdapp.get_lines
      #message "You entered #{desc}"
    end
    type = $default_type || "bug"
    severity = $default_severity || "normal"
    status = $default_status || "open"
    priority = $default_priority || "P3"
    if $prompt_type
      type = Cmdapp._choice("Select type:", %w[bug enhancement feature task] )
      #message "You selected #{type}"
    end
    if $prompt_priority
      #priority = Cmdapp._choice("Select priority:", %w[normal critical moderate] )
      priority = ask_priority
      #message "You selected #{severity}"
    end
    if $prompt_severity
      severity = Cmdapp._choice("Select severity:", %w[normal critical moderate] )
      #message "You selected #{severity}"
    end
    if $prompt_status
      status = Cmdapp._choice("Select status:", %w[open started closed stopped canceled] )
      #message "You selected #{status}"
    end
    assigned_to = $default_assigned_to
    if $prompt_assigned_to
      message "Assign to:"
      #assigned_to = $stdin.gets.chomp
      assigned_to = Cmdapp._gets "assigned_to", "assigned_to", $default_assigned_to
      #message "You selected #{assigned_to}"
    end
    project = component = version = nil
    # project
    if $use_project
      project = Cmdapp.user_input('project', $prompt_project, nil, $valid_project, $default_project)
    end
    if $use_component
      component = Cmdapp.user_input('component', $prompt_component, nil, $valid_component, $default_component)
    end
    if $use_version
      version = Cmdapp.user_input('version', $prompt_version, nil, $valid_version, $default_version)
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
    return unless $send_email
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
    puts "Description:"
    puts Cmdapp.indent(row['description'],3) if row['description']
    puts "\nAdded by #{row['created_by']} on #{row['date_created']}. Updated #{row['date_modified']}."
    comment_count = 0
    #puts row
    row.each_pair { |name, val| 
      x = (name =~ /[A-Za-z]/)
      next unless x # 2011-09-21 skip names that are just numbers
      next if name == "project" && !$use_project
      next if name == "version" && !$use_version
      next if name == "component" && !$use_component
      next if %w{ id title description created_by date_created date_modified }.include? name
      comment_count = val.to_i if name == "comment_count"
      val = Cmdapp.indent2(val, 18) if name == "fix"
      n = sprintf("%-15s", name); 
      puts "#{n} : #{val}" 
    }
    puts
    if comment_count > 0
      puts "Comments   :"
      ctr = 0
      db.select_where "comments", "id", id do |r|
        #puts "(#{r['date_created']}) [ #{r['created_by']} ] #{r['comment']}"
        ctr += 1
        puts "------- (#{r['date_created']}) #{r['created_by']} (#{ctr})------"
        puts r['comment']
      end
      puts
    end
    puts "Log:"
      ctr = 0
      db.select_where "log", "id", id do |r|
          ctr += 1
          #puts "------- (#{r['date_created']}) #{r['created_by']}  ------"
          puts "------- #{r['date_created']} - #{r['created_by']} (#{ctr})------"
          puts " * [#{r['field']}]:  #{r['log']} "
      end
      #pp r
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
    print_green row['title']
    print_green row['description'] if row['description']
    sel = Cmdapp._choice "Select field to edit", editable
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
    if sel == 'status' && ['canceled', 'closed'].include?(str)
      curr_status = row['priority']
      value = curr_status.sub(/P/,'X')
      db.sql_update "bugs", id, 'priority', value
      puts "Updated #{id}'s PRI from #{str} to #{value} "
    end
    sstr = Cmdapp.truncate(str.to_s,50)
    rowid = db.sql_logs_insert id, sel, "[#{id}] updated [#{sel}] with #{sstr}"
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
  # view logs for a given id, or highest issue
  # @param [Array] issue id
  def viewlogs args=nil
    db = get_db
    id = args[0].nil? ? db.max_bug_id : args[0]
    row = db.sql_select_rowid "bugs", id
    die "No data found for #{id}" unless row
    puts "[#{row['type']} \##{row['id']}] #{row['title']}"
    puts row['description'] if row['description']
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
    # will not be able to find title due to function
    descdelim = '>>'
    #fields = 'id,status,type,priority,substr(title || "  >>" ||  ifnull(description,""),0,85)'
    fields = %Q[id,status,type,priority,substr(title || "  #{descdelim}" ||  ifnull(description,""),0,85)]
    format = "%-3s | %-7s | %-5s | %-60s "
    if @options[:short]
      fields = "id,status,title"
      format = "%3s | %6s | %60s "
    elsif @options[:long]
      fields = "id,status,priority,title,description"
      format = "%-3s|%-7s|%-5s | %-60s |%-s"
    end
    fieldsarr = fields.split(",") # NOTE comma in ifnull function
    descindex = fieldsarr.index("description")
    titleindex = fieldsarr.index("title")  || 4 # fieldsarr.count-1 due to comman in ifnull XXX NOTE
    statindex =  fieldsarr.index("status")
    priindex =  fieldsarr.index("priority")
    typeindex =  fieldsarr.index("type")

    where = nil
    wherestring = ""
    if @options[:open]
      where ||= []
      where <<  %{ status != 'closed'} 
    end
    if @options[:overdue]
      #where =  %{ where status != 'closed' and due_date <= "#{Date.today}" }
      where ||= []
      where <<  %{ status != 'closed' and status != 'canceled'} 
      where <<  %{ due_date <= "#{Date.today}" }
    end
    if @options[:unassigned]
      #where =  %{ where status != 'closed' and due_date <= "#{Date.today}" }
      where ||= []
      where <<  %{ (assigned_to = 'unassigned' or assigned_to is null) } 
    end
    # added 2011-09-28 so we don't see closed all the time.
    if !where && !@options[:show_all]
      where ||= []
      where <<  %{ status != 'closed' and status != 'canceled'} 
    end
    if where
      wherestring = " where " + where.join(" and ")
    end
    orderstring ||= " order by status asc, priority desc " # 2011-09-30  so highest prio comes at end
    puts wherestring if @options[:verbose]

    db.db.type_translation = true
    db.db.results_as_hash = false # 2011-09-21 
    rows = db.run "select #{fields} from bugs #{wherestring} #{orderstring}  "
    db.db.type_translation = false
    die "No rows" unless rows

    rows = Cmdapp.filter_rows( rows, incl) do |row, regexp|
      #row['title'] =~ regexp
      row[titleindex] =~ regexp
    end
    rows = Cmdapp.filter_rows( rows, excl) do |row, regexp|
      #row['title'] !~ regexp
      row[titleindex] !~ regexp
    end
    fields.sub!( /priority/, "pri")
    fields.sub!( /status/, "sta")
    fields.sub!( /severity/, "sev")
    fields.sub!( /substr.*/, "title") # XXX depends on function used on title
    headings = fields.split ","
    # if you want to filter output send a delimiter
    if $bare
      delim = @options[:delimiter] || "\t" 
      puts headings.join delim
      rows.each do |e| 
#        d = e['description']  # changed 2011 dts  
        if descindex
          d = e[descindex] 
          e[descindex].gsub!(/\n/," ") if d
        end
        e[typeindex] = e[typeindex][0,3] if typeindex
        e[statindex] = e[statindex][0,2] if statindex
        puts e.join delim
      end
    else
      if rows.size == 0
        puts "No rows"
        return
      end
      # NOTE: terminal table gets the widths wrong because of coloring info.
      if @options[:colored]
        #require 'colored'
        startrow = nil
        fr = titleindex
        rows.each_with_index do |e, index|  
          s = e[titleindex] 
          s.gsub!("\n", ";")
          s.gsub!(/(#\w+)/,"#{UNDERLINE}\\1#{UNDERLINE_OFF}")
          s.gsub!(/(>>.*)/,"#{GREEN}\\1#{CLEAR}")
          st = e[statindex]
          e[statindex] = e[statindex][0,2]
          e[typeindex] = e[typeindex][0,3] if typeindex
          if typeindex
            case e[typeindex]
            when 'bug'
              e[typeindex] = "#{RED}#{e[typeindex]}#{CLEAR}"
            when 'enh'
              e[typeindex] = "#{WHITE}#{e[typeindex]}#{CLEAR}"
            else
              e[typeindex] = "#{CYAN}#{e[typeindex]}#{CLEAR}"
            end
          end
          frv = e[fr]
          if st == 'started'
            startrow = index unless startrow
            e[fr] = "#{STANDOUT}#{frv}" # changed 2011 dts   whole line green
            #e[0] = e[0].to_s.red

            e[-1] = "#{e[-1]}#{CLEAR}"
          else
            if priindex
              pri = e[priindex]
              case pri
              when "P4", "P5"
                e[fr] = "#{BLUE}#{frv}"
                e[-1] = "#{e[-1]}#{CLEAR}"
              when "P1"
                e[fr] = "#{YELLOW}#{ON_RED}#{frv}"
                e[-1] = "#{e[-1]}#{CLEAR}"
              when "P2"
                e[fr] = "#{BOLD}#{frv}"
                e[-1] = "#{e[-1]}#{CLEAR}"
              else
            #e[fr] = "#{CLEAR}#{frv}"
              end
            end
          end

          #print "#{format}\n" % e
        end
        rows.insert(startrow, :separator) if startrow
        #return
      end
      # pretty output tabular format etc
      require 'terminal-table/import'
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
      puts row['description'] if row['description']
      puts 
    end
    return db, row
  end
  def putxx *args
    puts "GOT:: #{args}"
  end
  def ask_type old=nil
    type = Cmdapp._choice("Select type:", %w[bug enhancement feature task] )
  end
  def ask_severity old=nil
    severity = Cmdapp._choice("Select severity:", %w[normal critical moderate] )
  end
  def ask_status old=nil
    status = Cmdapp._choice("Select status:", %w[open started closed stopped canceled] )
  end
  def ask_priority old=nil
    priority = Cmdapp._choice("Select priority:", %w[P1 P2 P3 P4 P5] )
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
    db, row = validate_id id, true
    die "No issue found for #{id}" unless row
    if !args.empty?
      comment = args.join(" ")
    else
      message "Enter a comment (. to exit): "
      comment = Cmdapp.get_lines
    end
    die "Operation cancelled" if comment.nil? or comment.empty?
    message "Comment is: #{comment}."
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
    rowid = db.sql_logs_insert id, "comment", Cmdapp.truncate(text, 50)
  end
  # prompts user for a fix related to an issue
  # # XXX what if fix already exists, will we overwrite.
  def fix args #id, fix
    id = args.shift
    unless id
      id = ask("Issue Id?  ", Integer)
    end
    db, row = validate_id id
    if !args.empty?
      text = args.join(" ")
      if row['fix']
        die "Sorry. I already have a fix, pls edit ... #{row['fix']}"
      end
    else
      # XXX give the choice of using vim
      if row['fix']
        text = Cmdapp.edit_text row['fix']
      else
        message "Enter a fix (. to exit): "
        text = Cmdapp.get_lines
      end
    end
    # FIXME: what if user accidentally enters a fix, and wants to nullify ?
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
    rowid = db.sql_logs_insert id, "fix", Cmdapp.truncate(text, 50)
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
    args.each do |id| 
      db, row = validate_id id
      curr_status = row['priority']
      value = curr_status.sub(/P/,'X')
      db.sql_update "bugs", id, 'priority', value
      puts "Updated #{id}'s PRI from #{curr_status} to #{value} "
    end
    0
  end

  # start an issue (changes status of issue/s)
  # @param [Array] array of id's to start (argv)
  # @return [0] for success
  def start args
    change_value "status", "started", args
    0
  end
  def priority args
    value = args.shift
    ret = change_value "priority", value, args
    if ret != 0
      die "#{value} is not valid for priority. Valid are (#{@valid_priority.join(',')})" 
    end
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


  def test args=nil
    puts "This is only for testing things out"
    if $use_project
      project = Cmdapp.user_input('project', $prompt_project, nil, $valid_project, $default_project)
      puts project
    end
    if $use_component
      component = Cmdapp.user_input('component', $prompt_component, nil, $valid_component, $default_component)
      puts component
    end
  end
  #
  # prints recent log/activity
  # @param [Array] first index is limit (how many rows to show), default 10
  def recentlogs args=nil
    limit = args[0] || 10
    sql = "select log.id, title, log.created_by, log.date_created, log from log,bugs where bugs.id = log.id  order by log.date_created desc limit #{limit}"

    db = get_db
    db.db.results_as_hash = true # 2011-09-21 
    db.run sql do |row|
      log = Cmdapp.indent2( row['log'],20)
      text = <<-TEXT

       id         : [#{row['id']}] #{row['title']} 
       action_by  : #{row['created_by']} 
       date       : #{row['date_created']} 
       activity   : #{log} 

      TEXT
      #puts row.keys
      puts text

    end
  end
  #
  # prints recent comments
  # @param [Array] first index is limit (how many rows to show), default 10
  def recentcomments args=nil
    limit = args[0] || 10
    sql = "select comments.id, title, comments.created_by, comments.date_created, comment from comments,bugs where bugs.id = comments.id  order by comments.date_created desc limit #{limit}"

    db = get_db
    db.db.results_as_hash = true # 2011-09-21 
    db.run sql do |row|
      comment = Cmdapp.indent2( row['comment'],20)
      text = <<-TEXT

       id         : [#{row['id']}] #{row['title']} 
       author     : #{row['created_by']} 
       date       : #{row['date_created']} 
       comment    : #{comment} 

      TEXT
      #puts row.keys
      puts text

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
      options[:colored] = true
      $bare = false
      # adding some env variable pickups, so you don't have to keep passing.
      showall = ENV["TODO_SHOW_ALL"]
      if showall
        options[:show_all] = (showall == "0") ? false:true
      end
      plain = ENV["TODO_PLAIN"]
      if plain
        options[:colored] = (plain == "0") ? false:true
      end
      config = File.expand_path "~/.bugzyrb.cfg"
      if File.exists? config
        options[:config] = config
        #puts "found  #{config} "
      end

  Subcommands::global_options do |opts|
    opts.banner = "Usage: #{APPNAME} [options] [subcommand [options]]"
    opts.description = "Bug list manager"
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
    opts.on("--list-actions", "list actions for autocompletion ") do |v|
      Subcommands::list_actions
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
    opts.description = "Add a comment to a given issue"
  end
  Subcommands::command :fix do |opts|
    opts.banner = "Usage: fix [options] ISSUE_NO TEXT"
    opts.description = "Add a fix for a given issue"
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
    opts.on("-c","--colored", "colored listing") { |v|
      options[:colored] = v
    }
    opts.on("-v","--overdue", "not closed, due date past") { |v|
      options[:overdue] = v
    }
    opts.on("-p","--open", "not closed") { |v|
      options[:open] = v
    }
    opts.on("-a","--show-all", "all items including closed") { |v|
      options[:show_all] = v
    }
    opts.on("-u","--unassigned", "not assigned") { |v|
      options[:unassigned] = v
    }
  end
  Subcommands::command :viewlogs do |opts|
    opts.banner = "Usage: viewlogs [options] ISSUE_NO"
    opts.description = "view logs for an issue"
  end
  Subcommands::command :recentlogs do |opts|
    opts.banner = "Usage: recentlogs [options] <HOWMANY>"
    opts.description = "view recent logs/activity, default last 10 logs "
  end
  Subcommands::command :recentcomments do |opts|
    opts.banner = "Usage: recentcomments [options] <HOWMANY>"
    opts.description = "view recent comments, default last 10 logs "
  end
  Subcommands::command :priority, :pri do |opts|
    opts.banner = "Usage: priority [options] <ISSUENO>"
    opts.description = "change priority of given items to [option]"
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
