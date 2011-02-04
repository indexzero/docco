# **Docco** is a quick-and-dirty, hundred-line-long, literate-programming-style
# documentation generator for JavaScript or CoffeeScript. It produces HTML
# that displays your comments alongside your code. Comments are passed through
# [Markdown](http://daringfireball.net/projects/markdown/syntax), and code is
# passed through [Pygments](http://pygments.org/) syntax highlighting.
# This page is the result of running Docco against its own source file.
#
# If you install Docco, you can run it from the command-line:
#
#     docco src/*.coffee
# or
#
#     docco src/*.js
#
# ...will generate linked HTML documentation for the named source files, saving
# it into a `docs` folder.
#
# The [source for Docco](http://github.com/jashkenas/docco) is available on GitHub,
# and released under the MIT license.
#
# To install Docco, first make sure you have [Node.js](http://nodejs.org/),
# [Pygments](http://pygments.org/) (install the latest dev version of Pygments
# from [its Mercurial repo](http://dev.pocoo.org/hg/pygments-main)), and
# [CoffeeScript](http://coffeescript.org/). Then, with NPM:
#
#     sudo npm install docco
#
# When used to process JavaScript files, docco will only process end of line (`//`)
# style comments, and only when they appear on a line by themselves.  Block comments
# (`/* ... */`) and end of line comments on the same line as code (`var x = 1 // like this`)
# are ignored by docco and will appear in your code.
#
# If **Node.js** doesn't run on your platform, or you'd prefer a more convenient
# package, get [Rocco](http://rtomayko.github.com/rocco/), the Ruby port that's
# available as a gem and processes `.rb` files. If you're writing shell scripts, try
# [Shocco](http://rtomayko.github.com/shocco/), a port for the **POSIX shell** (`.sh`).
# Both are by [Ryan Tomayko](http://github.com/rtomayko). If Python's more
# your speed, take a look at [Nick Fitzgerald](http://github.com/fitzgen)'s
# [Pycco](http://fitzgen.github.com/pycco/) which processes `.coffee`, `.js`, `.pl`,
# `.sql`, `.c`, `.rb`, `.py`, `.scm`, `.lua`, and `.erl`, and can handle multi-line comments.

#### Main Documentation Generation Functions

# Generate the documentation for a source file by reading it in, splitting it
# up into comment/code sections, highlighting them for the appropriate language,
# and merging them into an HTML template.
generate_documentation = (source, callback) ->
  fs.readFile source, "utf-8", (error, code) ->
    throw error if error
    sections = parse source, code
    highlight source, sections, ->
      generate_html source, sections
      callback()

# Given a string of source code, parse out each comment and the code that
# follows it, and create an individual **section** for it.
# Sections take the form:
#
#     {
#       docs_text: ...
#       docs_html: ...
#       code_text: ...
#       code_html: ...
#     }
#
parse = (source, code) ->
  lines    = code.split '\n'
  sections = []
  language = get_language source
  has_code = docs_text = code_text = ''

  save = (docs, code) ->
    sections.push docs_text: docs, code_text: code
  
  return unless language;
  
  for line in lines
    if line.match(language.comment_matcher) and not line.match(language.comment_filter)
      if has_code
        save docs_text, code_text
        has_code = docs_text = code_text = ''
      docs_text += line.replace(language.comment_matcher, '') + '\n'
    else
      has_code = yes
      code_text += line + '\n'
  save docs_text, code_text
  sections

# Highlights a single chunk of CoffeeScript code, using **Pygments** over stdio,
# and runs the text of its corresponding comment through **Markdown**, using the
# **Github-flavored-Markdown** modification of [Showdown.js](http://attacklab.net/showdown/).
#
# We process the entire file in a single call to Pygments by inserting little
# marker comments between each section and then splitting the result string
# wherever our markers occur.
highlight = (source, sections, callback) ->
  language = get_language source
  return unless language;
  
  pygments = spawn 'pygmentize', ['-l', language.name, '-f', 'html', '-O', 'encoding=utf-8']
  output   = ''
  pygments.stderr.addListener 'data',  (error)  ->
    console.error error if error
  pygments.stdout.addListener 'data', (result) ->
    output += result if result
  pygments.addListener 'exit', ->
    output = output.replace(highlight_start, '').replace(highlight_end, '')
    fragments = output.split language.divider_html
    for section, i in sections
      section.code_html = highlight_start + fragments[i] + highlight_end
      section.docs_html = showdown.makeHtml section.docs_text
    callback()
  pygments.stdin.write((section.code_text for section in sections).join(language.divider_text))
  pygments.stdin.end()

# Once all of the code is finished highlighting, we can generate the HTML file
# and write out the documentation. Pass the completed sections into the template
# found in `resources/docco.jst`
generate_html = (source, sections) ->
  title = path.basename source
  destination source, (dest, depth) -> 
    html  = docco_template {
      title: title, sections: sections, sources: files, path: path, source_file: source_file, depth: depth
    }
    console.log "docco: #{source} -> #{dest}"
    fs.writeFile dest, html

#### Helpers & Setup

# Require our external dependencies, including **Showdown.js**
# (the JavaScript implementation of Markdown).
fs       = require 'fs'
path     = require 'path'
showdown = require('./../vendor/showdown').Showdown
{spawn, exec} = require 'child_process'

# A list of the languages that Docco supports, mapping the file extension to
# the name of the Pygments lexer and the symbol that indicates a comment. To
# add another language to Docco's repertoire, add it here.
languages =
  '.coffee':
    name: 'coffee-script', symbol: '#'
  '.js':
    name: 'javascript', symbol: '//'
  '.rb':
    name: 'ruby', symbol: '#'
  '.py':
    name: 'python', symbol: '#'
  '.h':
    name: 'objc', symbol: '//'
  '.hs':
    name: 'haskell', symbol: '--'
  '.as':
    name: 'actionscript', symbol: '//'

# Build out the appropriate matchers and delimiters for each language.
for ext, l of languages

  # Does the line begin with a comment?
  l.comment_matcher = new RegExp('^\\s*' + l.symbol + '\\s?')

  # Ignore [hashbangs](http://en.wikipedia.org/wiki/Shebang_(Unix))
  # and interpolations...
  l.comment_filter = new RegExp('(^#![/]|^\\s*#\\{)')

  # The dividing token we feed into Pygments, to delimit the boundaries between
  # sections.
  l.divider_text = '\n' + l.symbol + 'DIVIDER\n'

  # The mirror of `divider_text` that we expect Pygments to return. We can split
  # on this to recover the original sections.
  # Note: the class is "c" for Python and "c1" for the other languages
  l.divider_html = new RegExp('\\n*<span class="c1?">' + l.symbol + 'DIVIDER<\\/span>\\n*')

# Get the current language we're documenting, based on the extension.
get_language = (source) -> languages[path.extname(source)]

# Compute the destination HTML path for an input source file path. If the source
# is `lib/example.coffee`, the HTML will be at `docs/example.html`
destination = (filepath, callback) ->
  dirs = path.dirname(filepath).split('/')
  dest = 'docs/'
  dest += dirs.slice(1).join('/') + '/' if settings.dirs
  ensure_directory dest, -> 
    dest += path.basename(filepath, path.extname(filepath)) + '.html'
    callback dest, dirs.length

source_file = (depth, filepath) ->
  dirs = path.dirname(filepath).split('/')
  dest = ''
  dest += new Array(depth).join('../') + dirs.slice(1).join('/') + '/' if settings.dirs
  dest += path.basename(filepath, path.extname(filepath)) + '.html'
  return dest

# Ensure that the destination directory exists.
ensure_directory = (dir, callback) ->
  exec 'mkdir -p ' + dir, -> callback()
  
read_source = (filepath, callback) ->
  fs.stat filepath, (err, stats) -> 
    child_files = fs.readdirSync(filepath) if stats.isDirectory()
    callback child_files

# Micro-templating, originally by John Resig, borrowed by way of
# [Underscore.js](http://documentcloud.github.com/underscore/).
template = (str) ->
  new Function 'obj',
    'var p=[],print=function(){p.push.apply(p,arguments);};' +
    'with(obj){p.push(\'' +
    str.replace(/[\r\t\n]/g, " ")
       .replace(/'(?=[^<]*%>)/g,"\t")
       .split("'").join("\\'")
       .split("\t").join("'")
       .replace(/<%=(.+?)%>/g, "',$1,'")
       .split('<%').join("');")
       .split('%>').join("p.push('") +
       "');}return p.join('');"

# Create the template that we will use to generate the Docco HTML page.
docco_template  = template fs.readFileSync(__dirname + '/../resources/docco.jst').toString()

# The CSS styles we'd like to apply to the documentation.
docco_styles    = fs.readFileSync(__dirname + '/../resources/docco.css').toString()

# The start of each Pygments highlight block.
highlight_start = '<div class="highlight"><pre>'

# The end of each Pygments highlight block.
highlight_end   = '</pre></div>'

# The set of all files known as we recursively walk any directories
files = []

# The settings passed in from the command line
settings = {}

# Run the script.
# For each source file passed in as an argument, generate the documentation.
generate = this.generate = (targets, options) -> 
  if targets.length
    ensure_directory 'docs', ->
      fs.writeFile 'docs/docco.css', docco_styles
      files = targets
      settings = options
      next_file = -> 
        file = files.shift()
        read_source file, (child_files) ->
          if child_files
            files = files.concat(child_files.map (child) -> path.join(file, child))
            require('eyes').inspect(files) if child_files.indexOf 'controller' != -1
            return next_file()
          generate_documentation file, next_file if files.length
      next_file()