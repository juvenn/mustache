require 'cgi'

class RTemplate
  # Helper method for quickly instantiating and rendering a view.
  def self.to_html
    new.to_html
  end

  # The path informs your RTemplate subclass where to look for its
  # corresponding template.
  def self.path=(path)
    @path = File.expand_path(path)
  end

  def self.path
    @path || '.'
  end

  # Templates are self.class.name.underscore + '.html' -- a class of
  # Dashboard would have a template (relative to the path) of
  # dashboard.html
  def template_file
    @template_file ||= self.class.path + '/' + underscore(self.class.to_s) + '.html'
  end

  def template_file=(template_file)
    @template_file = template_file
  end

  # The template itself. You can override this if you'd like.
  def template
    @template ||= File.read(template_file)
  end

  def template=(template)
    @template = template
  end

  # Pass a block to `debug` with your debug putses. Set the `DEBUG`
  # env variable when you want to run those blocks.
  #
  # e.g.
  #  debug { puts @context.inspect }
  def debug
    yield if ENV['DEBUG']
  end

  # A helper method which gives access to the context at a given time.
  # Kind of a hack for now, but useful when you're in an iterating section
  # and want access to the hash currently being iterated over.
  def context
    @context ||= {}
  end

  # Context accessors
  def [](key)
    context[key]
  end

  def []=(key, value)
    context[key] = value
  end

  # How we turn a view object into HTML. The main method, if you will.
  def to_html
    render template
  end

  # Partials are basically a way to render views from inside other views.
  def partial(name)
    # First we check if a partial's view class already exists
    klass = classify(name)

    if Object.const_defined? klass
      # If so we can cheat and render that
      Object.const_get(klass).to_html
    else
      # If not we need to render the file directly.
      render File.read(self.class.path + '/' + name + '.html'), context
    end
  end

  # template_partial => TemplatePartial
  def classify(underscored)
    underscored.split(/[-_]/).map { |part| part[0] = part[0].chr.upcase; part }.join
  end

  # TemplatePartial => template_partial
  def underscore(classified)
    string = classified.dup
    string[0] = string[0].chr.downcase
    string.gsub(/[A-Z]/) { |s| "_#{s.downcase}"}
  end

  # Parses our fancy pants, template HTML and returns normal HTMl with
  # all special {{tags}} and {{#sections}}replaced{{/sections}}.
  def render(html, context = {})
    # Set the context so #find and #context have access to it
    @context = context = (@context || {}).merge(context)

    debug do
      puts "in:"
      puts html.inspect
      puts context.inspect
    end

    # {{#sections}}okay{{/sections}}
    #
    # Sections can return true, false, or an enumerable.
    # If true, the section is displayed.
    # If false, the section is not displayed.
    # If enumerable, the return value is iterated over (a for loop).
    html = html.gsub(/\{\{\#(.+)\}\}\s*(.+)\{\{\/\1\}\}\s*/m) do |s|
      ret = find($1)

      if ret.respond_to? :each
        ret.map do |ctx|
          render($2, ctx).to_s
        end
      elsif ret
        # render the section with the present context
        render($2, context).to_s
      else
        ''
      end
    end

    # Re-set the @context because our recursion probably overwrote it
    @context = context

    # Comments are ignored
    html = html.gsub(/\{\{(![^\/#]+?)\}\}/, '')

    # Partials are pulled in relative to `path`
    html = html.gsub(/\{\{<([^\/#]+?)\}\}/) { partial($1) }

    # The triple mustache is unescaped.
    html = html.gsub(/\{\{\{([^\/#]+?)\}\}\}/) { find($1) }

    # The double mustache is escaped.
    html = html.gsub(/\{\{([^\/#]+?)\}\}/) { escape find($1) }

    debug do
      puts "out:"
      puts html.inspect
    end

    html
  end

  # Escape HTML.
  def escape(string)
    CGI.escapeHTML(string.to_s)
  end

  # Given an atom, finds a value. We'll check the current context (for both
  # strings and symbols) then call methods on the view object.
  def find(name)
    name = name.to_s.strip
    if @context.has_key? name
      @context[name]
    elsif @context.has_key? name.to_sym
      @context[name.to_sym]
    elsif respond_to? name
      send name
    else
      raise "Can't find #{name} in #{@context.inspect}"
    end
  end
end