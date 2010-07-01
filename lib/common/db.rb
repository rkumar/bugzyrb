#!/usr/bin/env ruby -w
require 'rubygems'
require 'sqlite3'
require 'pp'
require 'arrayfields'
module Database
  class DB

    def initialize dbname="bugzy.sqlite"
      raise "#{dbname} does not exist. Try --help" unless File.exists? dbname
      @db = SQLite3::Database.new(dbname)
      $now = Time.now
      $num = rand(100)
    end

    ## start of table bugs ##

    # returns many rows 
    # @param [Fixnum] id for table with 1:n rows
    # @return [Array, nil] array if rows, else nil
    def select table
      puts " --- #{table} ---  "
      @db.type_translation = true
      rows = []
      @db.execute( "select * from #{table} " ) do |row|
        if block_given?
          yield row
        else
          rows << row
        end
      end
      return nil if rows.empty?
      return rows
    end
    # returns many rows 
    # @param [String] sql statement
    # @return [Array, nil] array if rows, else nil
    def run text
      puts " --- #{text} ---  "
      @db.type_translation = true
      rows = []
      @db.execute( text ) do |row|
        if block_given?
          yield row
        else
          rows << row
        end
      end
      return nil if rows.empty?
      return rows
    end
    def select_where table, *wherecond
      #puts " --- #{table} --- #{wherecond} "
      @db.type_translation = true
      wherestr = nil
      rows = []
      if wherecond and !wherecond.empty?
        fields, values = separate_field_values wherecond
        #wherestr = "" unless wherestr
        wherestr = " where #{fields.join(" and ")} "
        if wherestr
          #puts " wherestr #{wherestr}, #{values} "
          #stmt = @db.prepare("select * from #{table} #{wherestr} ", *values)
          @db.execute( "select * from #{table} #{wherestr}", *values  ) do |row|
            if block_given?
              yield row
            else
              rows << row
            end
          end
        end
      end
      return nil if rows.empty?
      return rows
    end
  ## 
  # insert a issue or bug report into the database
  # @params
  # @return [Fixnum] last row id
  def bugs_insert(status, severity, type, assigned_to, start_date, due_date, comment_count, priority, title, description, fix)
    # id = $num
    # status = "CODE" 
    # severity = "CODE" 
    # type = "CODE" 
    # assigned_to = "CODE" 
    # start_date = $now
    # due_date = $now
    # comment_count = $num
    # priority = "CODE" 
    # title = "CODE" 
    # description = "Some long text" 
    # fix = "Some long text" 
    # date_created = $now
    # date_modified = $now
    @db.execute(" insert into bugs (  status, severity, type, assigned_to, start_date, due_date, comment_count, priority, title, description, fix ) values (  ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",  
                status, severity, type, assigned_to, start_date, due_date, comment_count, priority, title, description, fix )
    rowid = @db.get_first_value( "select last_insert_rowid();")
    return rowid
  end
  def max_bug_id
    id = @db.get_first_value( "select max(id) from bugs;")
    return id
  end
  def sql_comments_insert id, comment, date_cr = nil
    #date_created = date_cr | Time.now
    @db.execute("insert into comments (id, comment) values (?,?)", id, comment ) 
    rowid = @db.get_first_value( "select last_insert_rowid();")
    return rowid
  end
  def sql_logs_insert id, field, log
    #date_created = date_cr | Time.now
    @db.execute("insert into log (id, field, log) values (?,?,?)", id, field, log ) 
  end
  def sql_delete_bug id
    message "deleting #{id}"
    @db.execute( "delete from bugs where id = ?", id )
    @db.execute( "delete from comments where id = ?", id )
    @db.execute( "delete from logs where id = ?", id )
  end


    ## insert a row into bugs using an array
    # @param [Array] array containing values
    def sql_bugs_insert bind_vars
      # id, status, severity, type, assigned_to, start_date, due_date, comment_count, priority, title, description, fix, date_created, date_modified
      @db.execute( "insert into bugs values (  ? ,? ,? ,? ,? ,? ,? ,? ,? ,? ,? ,? ,? ,?  )", *bind_vars )
    end


    ##
    # update a row from bugs based on id, giving one fieldname and value
    # @param [Fixnum] id unique key
    # @param [String] fieldname 
    # @param [String] value to update
    # @example sql_bugs_update 9, :name, "Roger"
    def sql_update table, id, field, value
      @db.execute( "update #{table} set #{field} = ?, date_modified = ? where id = ?", value,$now, id)
    end

    # update a row from bugs based on id, can give multiple fieldnames and values
    # @param [Fixnum] id unique key
    # @return [Array] alternating fieldname and value
    # @example sql_bugs_update_mult 9, :name, "Roger", :age, 29, :country, "SWI"
    def sql_bugs_update_mult id, *fv
      fields = []
      values = []
      fv << "date_modified"
      fv << $now
      fv.each_with_index do |f, i| 
        if i % 2 == 0
          fields << "#{f} = ?"
        else
          values << f
        end
      end

      print( "update bugs set #{fields.join(" ,")} where id = ?", *values, id)
      @db.execute( "update bugs set #{fields.join(" ,")} where id = ?", *values, id)
    end
    # 
    # return a single row from table based on rowid
    # @param [String] table name
    # @param [Fixnum] rowid
    # @return [Array] resultset (based on arrayfield)
    def sql_select_rowid table, id
      # @db.results_as_hash = true
      return nil if id.nil? or table.nil?
      row = @db.get_first_row( "select * from #{table} where rowid = ?", id )
      return row
    end

    def separate_field_values array
      fields = []
      values = []
      array.each_with_index do |f, i| 
        if i % 2 == 0
          fields << "#{f} = ?"
        else
          values << f
        end
      end
      return fields, values
    end
    def dummy
       id = $num
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
       bugs_insert(status, severity, type, assigned_to, start_date, due_date, comment_count, priority, title, description, fix, date_created, date_modified)
      #bugs_insert(id, status, severity, type, assigned_to, start_date, due_date, comment_count, priority, title, description, fix, date_created, date_modified)
    end

  end # class
end # module
if __FILE__ == $PROGRAM_NAME
  include Database
  # some tests. change bugs with real name
  db = DB.new
  db.dummy
  puts  "\n------------ all row -----\n"
  #db.select "bugs" do |r|
    #puts r
    ##puts r.join(" | ")
  #end
  res = db.select "bugs" 
  if res
    puts "count: #{res.count}"
    #puts res.public_methods
    res.each do |e| 
      puts e.join(" | ")
    end
  end
  db.sql_update "bugs", 1, "fix", "A fix added at #{$now}"
  db.sql_bugs_update_mult 1, "title", "a new title #{$num}", "description", "a new description #{$num}"
  puts  "\n------------ one row -----\n "
  db.select_where "bugs", "id", 1 do |r|
    puts r.join(" | ")
  end

end # if
