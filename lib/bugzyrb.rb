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
    @app_default_action = "list"
    @file = @app_file_path = @options[:file] || "bugzy.sqlite"
    #@app_serial_path = File.expand_path("~/serial_numbers")
    @app_serial_path = "serial_numbers"
    @archive_path = "todo_archive.txt" 
    @deleted_path = "todo_deleted.txt"
    @todo_delim = "\t"
    @appname = File.basename( Dir.getwd ) #+ ".#{$0}"
    # in order to support the testing framework
    t = Time.now
    ut = ENV["TODO_TEST_TIME"]
    t = Time.at(ut.to_i) if ut
    @now = t.strftime("%Y-%m-%d %H:%M:%S")
    @today = t.strftime("%Y-%m-%d")
    @verbose = @options[:verbose]
    $valid_array = false
    # menu MENU
    # TODO: config
    # we need to read up from config file and update
  end
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
  ##
  # add an issue or bug
  # @params [Array] text of bug (ARGV), will be concatenated into single string
  # @return [0,1] success or fail
  # TODO: users should be able to switch on or off globals, and pass / change defaults
  # TODO: reading environ ENV and config file.
  def add args
    db = DB.new
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
      i_assigned_to = $stdin.gets
      message "You selected #{i_assigned_to}"
    end
    #status = "OPEN" 
    #severity = "CRI" 
    #type = "BUG" 
    #assigned_to = "rahul" 
    start_date = @now
    due_date = @now
    comment_count = 0
    priority ||= "P3" 
    title = i_title
    description = i_desc
    fix = nil #"Some long text" 
    #date_created = @now
    #date_modified = @now
    rowid = db.bugs_insert(i_status, i_severity, i_type, i_assigned_to, start_date, due_date, comment_count, priority, title, description, fix)
    puts "Issue #{rowid} created"
    0
  end
  ##
  # view details of a single issue/bug
  # @param [Array] ARGV, first element is issue number
  #                If no arg supplied then shows highest entry
  def view args
    db = DB.new
    id = args[0].nil? ? db.max_bug_id : args[0]
    row = db.sql_select_rowid "bugs", id
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
    end
  end
  def edit args
    db = DB.new
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
      print "Enter new value: "
      str = $stdin.gets
    end
    str = old if str.nil? or str == ""
    unless str
      message "Operation cancelled."
      exit 0
    end
    message "Updating:"
    message str
    db.sql_update "bugs", id, sel, str
    puts "Updated #{id}"
    0
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
    db = DB.new
    row = db.sql_select_rowid "bugs", id
    die "No issue found for #{id}" unless row
    message "Adding comment to #{id}: #{row['title']}"
    rowid = db.sql_comments_insert id, comment
    puts "Comment #{rowid} created"
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

  ##
  # add a subtask
  # @param [Array] 1. item under which to place, 2. text
  # @return [0,1] success or fail
  #
  # @example
  #    addsub 1 "A task"   
  #       => will get added as 1.1 or 1.2 etc
  #    addsub 1.3 "a task"
  #       => will get added as 1.3.x
  def addsub args
    under = args.shift
    text = args.join " "
    exit unless text
    #puts "under #{under} text: #{text} "
    lastlinect = nil
    lastlinetext = nil
    # look for last item below given task (if there is)
    Sed::egrep( [@app_file_path], Regexp.new("#{under}\.[0-9]+	")) do |fn,ln,line|
      lastlinect = ln
      lastlinetext = line
      puts line if @verbose 
    end
    if lastlinect
      verbose "Last line found #{lastlinetext} " 
      m = lastlinetext.match(/\.([0-9]+)	/)
      lastindex = m[1].to_i
      # check if it has subitems, find last one only for linecount
      Sed::egrep( [@app_file_path], Regexp.new("#{under}\.#{lastindex}\.[0-9]+	")) do |fn,ln,line|
        lastlinect = ln
      end
      lastindex += 1
      item = "#{under}.#{lastindex}"
    else
      # no subitem found, so this is first
      item = "#{under}.1"
      # get line of parent
      found = nil
      Sed::egrep( [@app_file_path], Regexp.new("#{under}	")) do |fn,ln,line|
        lastlinect = ln
        found = true
      end
      die "Task #{under} not found" unless found
    end
    die "Could not determine which line to insert under" unless lastlinect
    verbose "item is #{item} ::: line #{lastlinect} " 

    # convert actual newline to C-a. slash n's are escapes so echo -e does not muck up.
    text.tr! "\n", ''
    Kernel.print("Got '#{text}'\n") if @verbose
    paditem = _paditem(item)
    print "item no is:#{paditem}:\n" if @verbose
    priority = @options[:priority] ? " (#{@options[:priority]})" : ""
    project  = @options[:project]  ? " +#{@options[:project]}"   : ""
    component  = @options[:component]  ? " @#{@options[:component]}"   : ""
    level = (item.split '.').length
    indent = " " * (TABSTOP * (level-1))
    newtext=nil
    if @copying
      newtext="#{indent}#{item}#{@todo_delim}#{text}"
    else
      newtext="#{indent}#{paditem}#{@todo_delim}[ ]#{priority}#{project}#{component} #{text} (#{@today})"
    end
    raise "Cannot insert blank text. Programmer error!" unless newtext
    #_backup
    puts "Adding:"
    puts newtext
    Sed::insert_row(@app_file_path, lastlinect, newtext)
    return 0
  end
  def check_file filename=@app_file_path
    File.exists?(filename) or die "#{filename} does not exist in this dir. Use 'add' to create an item first."
  end
  ##
  # populates array with open tasks (or all if --show-all)
  # DO NOT USE in conjunction with save_array since this is only open tasks
  # Use load_array with save_array
  def populate
    $valid_array = false # this array object should not be saved
    check_file
    @ctr = 0
    @total = 0
    #CSV.foreach(@file,:col_sep => "\t") do |row|    # 1.9 2009-10-05 11:12 
    filelist = [@file]
    filelist << @archive_path if @options[:show_arch]
    filelist.each do |file| 
      File.open(file).each do |line|
        row = line.chomp.split "\t"
        @total += 1
        if @options[:show_all]
          @data << row
          @ctr += 1
        else
          unless row[1] =~ /^\[x\]/ 
            @data << row
            @ctr += 1
          end
        end
      end
    end
  end
  ##
  # filters output based on project and or component and or priority
  def filter
    project = @options[:project]
    component = @options[:component]
    priority = @options[:priority]
    if project
      r = Regexp.new "\\+#{project}"
      @data = @data.select { |row| row[1] =~ r }
    end
    if component
      r = Regexp.new "@#{component}"
      @data = @data.select { |row| row[1] =~ r }
    end
    if priority
      r = Regexp.new "\\(#{priority}\\)"
      @data = @data.select { |row| row[1] =~ r }
    end
  end
  def list args
    populate
    grep if @options[:grep]
    filter if @options[:filter]
    sort if @options[:sort]
    renumber if @options[:renumber]
    colorize # << currently this is where I print !! Since i colorize the whole line
    puts " " 
    puts " #{@data.length} of #{@total} rows displayed from #{@app_file_path} "
    return 0
  end
  def print_todo
    @ctr = 0
    @data.each { |row|  
      unless row[1] =~ /^\[x\]/ 
        puts " #{row[0]} | #{row[1]} " #unless row[1] =~ /^\[x\]/
        @ctr += 1
      end
    }
  end
  def each
    @data.each { |row|  
        yield row
    }
  end
  def active_tasks
    @ctr = 0
    @data.each { |row|  
      unless row[1] =~ /^\[x\]/ 
        yield row
        @ctr += 1
      end
    }
  end
  ##
  # colorize each line, if required.
  # However, we should put the colors in some Map, so it can be changed at configuration level.
  #
  def colorize
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
  def sort
    fold_subtasks
    if @options[:reverse]
      @data.sort! { |a,b| a[1] <=> b[1] }
    else
      @data.sort! { |a,b| b[1] <=> a[1] }
    end
    unfold_subtasks
  end
  def grep
    r = Regexp.new @options[:grep]
    #@data = @data.grep r
    @data = @data.find_all {|i| i[1] =~ r }
  end
  ##
  # Adds or changes priority for a task
  #
  # @param [Array] priority, single char A-Z, item or items
  # @return [0,1] success or fail
  # @example
  # pri A 5 6 7
  # pri 5 6 7 A
  # -- NO LONGER this complicated system  pri A 5 6 7 B 1 2 3
  # -- NO LONGER this complicated system  pri 5 6 7 A 1 2 3 B

  # 2010-06-19 15:21 total rewrite, so we fetch item from array and warn if absent.
  def pri args
    errors = 0
    ctr = 0
    #populate # populate removed closed task so later saving will lose tasks
    load_array
    ## if the first arg is priority then following items all have that priority
    ## if the first arg is item/s then wait for priority and use that
    prior, items = _separate args, /^[A-Z]$/ 
    total = items.count
    die "#{@action}: priority expected [A-Z]" unless prior
    die "#{@action}: items expected" unless items
    verbose "args 0 is #{args[0]}. pri #{prior} items #{items} "
    items.each do |item| 
      row = get_item(item)
      if row
        puts " #{row[0]} : #{row[1]} "
        # remove existing priority if there
        if row[1] =~ /\] (\([A-Z]\) )/
          row[1].sub!(/\([A-Z]\) /,"")
        end
        ret = row[1].sub!(/\] /,"] (#{prior}) ")
        if ret
          puts " #{GREEN}#{row[0]} : #{row[1]} #{CLEAR}"
          ctr += 1
        else
          die "Error in sub(): #{row}.\nNothing saved. "
        end
      else
        errors += 1
        warning "#{item} not found."
      end
    end

    message "#{errors} error/s" if errors > 0
    if ctr > 0
      puts "Changed priority of #{ctr} task/s"
      save_array 
      return 0 
    end
    return ERRCODE
  end
  ##
  # Remove the priority of a task
  #
  # @param [Array] items to deprioritize
  # @return [0,1] success or fail
  def depri(args)
    change_items args, /\([A-Z]\) /,""
  end
  ##
  # Appends a tag to task
  #
  # @param [Array] items and tag, or tag and items
  # @return [0,1] success or fail
  def tag(args)
    tag, items = _separate args
    #change_items items do |item, row|
      #ret = row[1].sub!(/ (\([0-9]{4})/, " @#{tag} "+'\1')
      #ret
    #end
    change_items(items, / (\([0-9]{4})/, " @#{tag} "+'\1')
  end
  ##
  # deletes one or more items
  #
  # @param [Array, #include?] items to delete
  # @return [0,1] success or fail
  public
  def delete(args)
    ctr = errors = 0
    items = args
    die "#{@action}: items expected" unless items
    total = items.count
    totalitems = []
    load_array
    items.each do |item| 
      if @options[:recursive]
        a = get_item_subs item
        if a
          a.each { |e| 
            totalitems << e; #e[0].strip
          }
        else
          errors += 1
          warning "#{item} not found."
        end
      else
        row = get_item(item)
        if row
          totalitems << row
        else
          errors += 1
          warning "#{item} not found."
        end
      end
    end
    totalitems.each { |item| 
      puts "#{item[0]} #{item[1]}"
      ans = nil
      if @options[:force]
        ans = "Y"
      else
        $stderr.print "Do you wish to delete (Y/N/A/q): "
        STDOUT.flush
        ans = STDIN.gets.chomp
        # A means user specified ALL, don't keep asking
        if ans =~ /[Aa]/
          ans = "Y"
          @options[:force] = true
        elsif ans =~ /[qQ]/
          $stderr.puts "Operation canceled. No tasks deleted."
          exit 1
        end
      end
      if ans =~ /[Yy]/
        @data.delete item
        # put deleted row into deleted file, so one can undo
        File.open(@deleted_path, "a") { | file| file.puts "#{item[0]}#{@todo_delim}#{item[1]}" }
        ctr += 1
      else
        puts "Delete canceled #{item[0]}"
      end
    }
    message "#{errors} error/s" if errors > 0
    if ctr > 0
      puts "Deleted #{ctr} task/s"
      save_array 
      return 0 
    end
    return ERRCODE
  end
  ##
  # Change status of given items
  #
  # @param [Array, #include?] items to change status of
  # @return [0,1] success or fail
  public
  def status(args)
    stat, items = _separate args #, /^[a-zA-Z]/ 
    verbose "Items: #{items} : stat #{stat} "
    status, newstatus = _resolve_status stat
    if status.nil?
      die "Status #{stat} is invalid!"
    end
    # this worked fine for single items, but not for recursive changes 
    #ctr = change_items(items, /(\[.\])/, "[#{newstatus}]")
    totalitems = []
    #ret = line.sub!(/(\[.\])/, "[#{newstatus}]")
    load_array
    items.each { |item| 
      a = get_item_subs item
      if a
        a.each { |e| 
          totalitems << e[0].strip
        }
      else
        # perhaps I should pass item into total and let c_i handle error message
        warning "No tasks found for #{item}"
      end
    }
    change_items(totalitems, /(\[.\])/, "[#{newstatus}]")
    0
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
  ##
  # Renumber while displaying
  # @return [0,1] success or fail
  private
  def renumber
    ## this did not account for subtasks
    #@data.each_with_index { |row, i| 
      #paditem = _paditem(i+1)  
      #row[0] = paditem
    #}
    ## this accounts for subtasks
    ctr = 0
    @data.each_with_index { |row, i| 
      # main task, increment counter
      if row[0] =~ /^ *[0-9]+$/
        ctr += 1
        paditem = _paditem(ctr)  
        row[0] = paditem
      else
        # assume its a subtask, just change the outer number
        row[0].sub!(/[0-9]+\./, "#{ctr}.")
      end
    }
  end
  ##
  # For given items, add a note
  #
  # @param [Array, #include?] items to add note to, note
  # @return [0, 1] success or fail
  public
  def note(args)
    _backup
    text = args.pop
    change_items args do |item, row|
      m = row[0].match(/^ */)
      indent = m[0]
      ret = row[1].sub!(/ (\([0-9]{4})/," #{indent}* #{text} "+'\1')
      ret
    end
    0
  end
  ##
  # Archive all closed items
  #
  # @param none (ignored)
  # @return [0, 1] success or fail
  public
  def archive(args=nil)
    filename = @archive_path
    file = File.open(filename, "a") 
    ctr = 0
    Sed::delete_row @app_file_path do |line|
      if line =~ /\[x\]/
        file.puts line
        ctr += 1
        puts line if @verbose
        true
      end
    end
    file.close
    puts "Archived #{ctr} tasks."
    0
  end
  # Copy given item under second item
  #
  # @param [Array] 2 items, move first under second
  # @return [0,1] success or fail
  public
  def copyunder(args)
    if args.nil? or args.count != 2
      die "copyunder expects only 2 args: from and to item, both existing"
    end
    from = args[0]
    to = args[1]
    # extract item from
    lastlinetext = nil
    rx = regexp_item from
    Sed::egrep( [@app_file_path], rx) do |fn,ln,line|
      lastlinect = ln
      lastlinetext = line
      puts line
    end
    # removing everything from start to status inclusive
    lastlinetext.sub!(/^.*\[/,'[').chomp!
    puts lastlinetext
    @copying = true
    addsub [to, lastlinetext]
    # remove item number and status ? 
    # give to addsub to add.
    # delete from
    #  The earlier todoapp.sh  was not deleting, so we don't. We just copy
    delete_item(from) if @options[:delete_old]
  end
  ##
  # Get row for given item or nil.
  #
  # @param [String] item to retrieve
  # @return [Array, nil] success or fail
  # Returns row from @data as String[2] comprising item and rest of line.
  public
  def get_item(item)
    raise "Please load array first!" if @data.empty?
    puts "get_item got #{item}." if @verbose
    #rx = regexp_item(item)
    rx = Regexp.new("^ +#{item}$")
    @data.each { |row|
      puts "    get_item read #{row[0]}." if @verbose 
      return row if row[0] =~ rx
    }
    # not found
    return nil
  end
  ## 
  # list task and its subtasks
  #  just testing this out
  def listsub(args)
    load_array
    args.each { |item|  
      a = get_item_subs item
      puts "for #{item} "
      a.each { |e| puts " #{e[0]} #{e[1]} " }
    }
    0
  end
  # get item and its subtasks
  # (in an attempt to make recursive changes cleaner)
  # @param item (taken from command line)
  # @return [Array, nil] row[] objects
  def get_item_subs(item)
    raise "Please load array first!" if @data.empty?
    verbose "get_item got #{item}."
    #rx = regexp_item(item)
    rx = Regexp.new("^ +#{item}$")
    rx2 = Regexp.new("^ +#{item}\.")
    rows = []
    @data.each { |row|
      verbose "    get_item read #{row[0]}."
      if row[0] =~ rx
        rows << row 
        rx = rx2
      end
    }
    return nil if rows.empty?
    return rows
  end
  ##
  # For given items, search replace or yield item and row[]
  # (earlier started as new_change_items)
  #
  # @param [Array, #each] items to change
  # @yield item, row[] - split of line on tab.
  # @return [0, ERRCODE] success or fail
  public
  def change_items items, pattern=nil, replacement=nil
    ctr = errors = 0
    #tag, items = _separate args
    # or items = args
    die "#{@action}: items expected" unless items
    total = items.count
    load_array
    items.each do |item| 
      row = get_item(item)
      if row
        if pattern
          puts " #{row[0]} : #{row[1]} " if @verbose 
          ret = row[1].sub!(pattern, replacement)
          if ret
            puts " #{GREEN}#{row[0]} : #{row[1]} #{CLEAR}"
            ctr += 1
          else
            # this is since there could be a programmer error.
            die "Possible error in sub() - No replacement: #{row[0]} : #{row[1]}.\nNothing saved. "
          end
        else
          puts " #{row[0]} : #{row[1]} " if @verbose 
          ret = yield item, row
          if ret
            ctr += 1 
            puts " #{GREEN}#{row[0]} : #{row[1]} #{CLEAR}"
          end
        end
      else
        errors += 1
        warning "#{item} not found."
      end
    end
    message "#{errors} error/s" if errors > 0
    if ctr > 0
      puts "Changed #{ctr} task/s"
      save_array 
      return 0 
    end
    return ERRCODE
  end
  ## does a straight delete of an item, no questions asked
  # internal use only.
  def delete_item item
    filename=@app_file_path
    d = Sed::_read filename
    d.delete_if { |row| line_contains_item?(row, item) }
    Sed::_write filename, d
  end
  def line_contains_item? line, item
    rx = regexp_item item
    return line.match rx
  end
  def row_contains_item? row, item
    rx = Regexp.new("^ +#{item}")
    return row[0].match rx
  end
  # return a regexp for an item to do matches on - WARNING INCLUDES TAB
  def regexp_item item
    Regexp.new("^ +#{item}#{@todo_delim}")
  end
  # unused - wrote so i could use it refactoring -  i should be using this TODO:
  def extract_item line
      item = line.match(/^ *([0-9\.]+)/)
      return nil if item.nil?
      return item[1]
  end
  ##
  # Redoes the numbering in the file.
  # Useful if the numbers have gone high and you want to start over.
  # @return [0,1] success or fail
  def redo args
    #require 'fileutils'
    #FileUtils.cp @app_file_path, "#{@app_file_path}.org"
    _backup
    puts "Saved #{@app_file_path} as #{@app_file_path}.org"
    #ctr = 1
    #change_file @app_file_path do |line|
      #paditem = _paditem ctr
      #line.sub!(/^ *[0-9]+/, paditem)
      #ctr += 1
    #end
    ctr = 0
    Sed::change_file @app_file_path do |line|
      if line =~ /^ *[0-9]+\t/
        ctr += 1
        paditem = _paditem ctr
        line.sub!(/^ *[0-9]+\t/, "#{paditem}#{@todo_delim}")
      else
        # assume its a subtask, just change the outer number
        line.sub!(/[0-9]+\./, "#{ctr}.")
      end
    end
    _set_serial_number ctr+1
    puts "Redone numbering"
    0
  end
  ##
  private
  def _resolve_status stat
    status = nil
    #puts " got #{stat} "
    case stat
    when "@","sta","star","start","started"
          status="start"
          newstatus = "@"
    when "P","pen","pend","pending"
          status="pend"
          newstatus = "P"
    when "x","clo","clos","close","closed"
          status="close"
          newstatus = "x"
    when "1","next"
      status="next"
      newstatus = "1"
    when "H","hold" 
      status="hold"
      newstatus = "H"
    when "u","uns","unst","unstart","unstarted","open" 
      status="unstarted"
      newstatus = " "
    end
    #puts " after #{status} "
    #newstatus=$( echo $status | sed 's/^start/@/;s/^pend/P/;s/^close/x/;s/hold/H/;s/next/1/;s/^unstarted/ /' )
    return status, newstatus
  end

  def _choice prompt, choices
    #HighLine.track_eof = false
    #if $stdin.eof?
      #$stdin.reopen '/dev/tty'
      ##$stdin.reopen 'read'
    #end
    #puts "got: #{prompt} ::: #{choices} "
    #$stdin.flush
    choose do |menu|
      menu.prompt = prompt
      menu.choices(*choices) do |n|  return n; end
    end
  end
  def xxxsql_bug_insert
    #id = $num
    status = "OPEN" 
    severity = "CRI" 
    type = "BUG" 
    assigned_to = "rahul" 
    start_date = $now
    due_date = $now
    comment_count = 0
    priority = "A" 
    title = "some title" 
    description = "Some long text fro this bug too" 
    fix = nil #"Some long text" 
    date_created = $now
    date_modified = $now
    return bugs_insert(status, severity, type, assigned_to, start_date, due_date, comment_count, priority, title, description, fix, date_created, date_modified)
    #bugs_insert(id, status, severity, type, assigned_to, start_date, due_date, comment_count, priority, title, description, fix, date_created, date_modified)
  end
  def sql_select_first_row sql
    @db.type_translation = true
    row = @db.get_first_row( sql )
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
        #{APPNAME} pri 1 A
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
    opts.on("-p", "--priority A-Z",  "priority code for add or list") { |v|
      options[:priority] = v
      options[:filter] = true
    }
    opts.on("-C", "--component COMPONENT",  "component name for add or list") { |v|
      options[:component] = v
      options[:filter] = true
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
  # XXX order of these 2 matters !! reverse and see what happens
  Subcommands::command :pri, :p do |opts|
    opts.banner = "Usage: pri [options] [A-Z] <TASK/s>"
    opts.description = "Add priority to task. "
    opts.on("-f", "--[no-]force", "force verbosely") do |v|
      options[:force] = v
    end
  end
  Subcommands::command :depri do |opts|
    opts.banner = "Usage: depri [options] <TASK/s>"
    opts.description = "Remove priority of task. \n\t bugzyrb depri <TASK>"
    opts.on("-f", "--[no-]force", "force verbosely") do |v|
      options[:force] = v
    end
  end
  Subcommands::command :delete, :del do |opts|
    opts.banner = "Usage: delete [options] <TASK/s>"
    opts.description = "Delete a task. \n\t bugzyrb delete <TASK>"
    opts.on("-f", "--[no-]force", "force - don't prompt") do |v|
      options[:force] = v
    end
    opts.on("--recursive", "operate on subtasks also") { |v|
      options[:recursive] = v
    }
  end
  Subcommands::command :status do |opts|
    opts.banner = "Usage: status [options] <STATUS> <TASKS>"
    opts.description = "Change the status of a task. \t<STATUS> are open closed started pending hold next"
    opts.on("--recursive", "operate on subtasks also") { |v|
      options[:recursive] = v
    }
  end
  Subcommands::command :redo do |opts|
    opts.banner = "Usage: redo"
    opts.description = "Renumbers the todo file starting 1"
  end
  Subcommands::command :note do |opts|
    opts.banner = "Usage: note <TASK> <TEXT>"
    opts.description = "Add a note to a task."
  end
  Subcommands::command :tag do |opts|
    opts.banner = "Usage: tag <TAG> <TASKS>"
    opts.description = "Add a tag to an item/s. "
  end
  Subcommands::command :archive do |opts|
    opts.banner = "Usage: archive"
    opts.description = "archive closed tasks to archive.txt"
  end
  Subcommands::command :copyunder, :cu do |opts|
    opts.banner = "Usage: copyunder"
    opts.description = "Move first task under second (as a subtask). aka cu"
    opts.on("-d", "--delete", "Delete old after copying") do |v|
      options[:delete_old] = v
    end
  end
  Subcommands::command :addsub do |opts|
    opts.banner = "Usage: addsub [options]"
    opts.description = "Add a task under another."
    opts.on("-P", "--project PROJECTNAME", "name of project for add or list") { |v|
      options[:project] = v
      #options[:filter] = true
    }
    opts.on("-p", "--priority A-Z",  "priority code for add or list") { |v|
      options[:priority] = v
      #options[:filter] = true
    }
    opts.on("-C", "--component COMPONENT",  "component name for add or list") { |v|
      options[:component] = v
      #options[:filter] = true
    }
  end
  #Subcommands::command :testy do |opts|
    #opts.banner = "Usage: test"
    #opts.description = "test out some functionality"
  #end
  Subcommands::alias_command :open , "status","open"
  Subcommands::alias_command :close , "status","closed"
  cmd = Subcommands::opt_parse()
  args.unshift cmd if cmd

  if options[:verbose]
    p options
    print "ARGV: " 
    p args #ARGV 
  end
  #raise "-f FILENAME is mandatory" unless options[:file]

  todo = Bugzy.new(options, args)
  ret = todo.run
    ensure
    end
  return ret
  end # main
end # class Bugzy

if __FILE__ == $0
  exit Bugzy.main(ARGV) 
end
