path = require 'path'
_ = require 'underscore-plus'
cheerio = require 'cheerio'
fs = require 'fs-plus'
Highlights = require 'highlights'
{$} = require 'atom-space-pen-views'
roaster = null # Defer until used
{scopeForFenceName} = require './extension-helper'

highlighter = null
{resourcePath} = atom.getLoadSettings()
packagePath = path.dirname(__dirname)

exports.toHtml = (text='', filePath, grammar, callback) ->
  roaster ?= require 'roaster'
  options =
    sanitize: false
    breaks: atom.config.get('fountain-preview.breakOnSingleNewline')

  # Remove the <!doctype> since otherwise marked will escape it
  # https://github.com/chjj/marked/issues/354
  text = text.replace(/^\s*<!doctype(\s+.*)?>\s*/i, '')

  complete = (error, html) =>
    return callback(error) if error

    grammar ?= atom.grammars.selectGrammar(filePath, text)
    # Default code blocks to be coffee in Literate CoffeeScript files
    defaultCodeLanguage = 'coffee' if grammar.scopeName is 'source.litcoffee'

    html = sanitize(html)
    html = resolveImagePaths(html, filePath)
    html = tokenizeCodeBlocks(html, defaultCodeLanguage)
    callback(null, html.html().trim())

  ext = ".fountain"
  if filePath.indexOf(ext) == filePath.length - ext.length
    fountain = require 'fountain-js'
    fountain.parse text, (o) =>
      html = ''
      html += '<div id="workspace">'
      html += '<div id="script">'

      if o.title_page_html?.length > 0
        html += '<div class="page title-page">'
        html += o.title_page_html
        html += '</div>'

      html += o.script_html

      html += '</div>'
      html += '</div>'

      complete(null, html)
  else
    roaster text, options, complete

exports.toText = (text, filePath, grammar, callback) ->
  exports.toHtml text, filePath, grammar, (error, html) ->
    if error
      callback(error)
    else
      string = $(document.createElement('div')).append(html)[0].innerHTML
      callback(error, string)

sanitize = (html) ->
  o = cheerio.load("<div>#{html}</div>")
  o('script').remove()
  attributesToRemove = [
    'onabort'
    'onblur'
    'onchange'
    'onclick'
    'ondbclick'
    'onerror'
    'onfocus'
    'onkeydown'
    'onkeypress'
    'onkeyup'
    'onload'
    'onmousedown'
    'onmousemove'
    'onmouseover'
    'onmouseout'
    'onmouseup'
    'onreset'
    'onresize'
    'onscroll'
    'onselect'
    'onsubmit'
    'onunload'
  ]
  o('*').removeAttr(attribute) for attribute in attributesToRemove
  o.html()

resolveImagePaths = (html, filePath) ->
  html = $(html)
  for imgElement in html.find('img')
    img = $(imgElement)
    if src = img.attr('src')
      continue if src.match(/^(https?|atom):\/\//)
      continue if src.startsWith(process.resourcesPath)
      continue if src.startsWith(resourcePath)
      continue if src.startsWith(packagePath)

      if src[0] is '/'
        unless fs.isFileSync(src)
          img.attr('src', atom.project.resolve(src.substring(1)))
      else
        img.attr('src', path.resolve(path.dirname(filePath), src))

  html

tokenizeCodeBlocks = (html, defaultLanguage='text') ->
  html = $(html)

  if fontFamily = atom.config.get('editor.fontFamily')
    $(html).find('code').css('font-family', fontFamily)

  # fix parentheticals
  $(html).find('.parenthetical').each (i, el) => $(el).insertBefore($(el).prev())

  splitIntoPages = (el) =>
    elements = [];
    $(el).children().each (j, child) =>
      elements.push $(child).detach() unless $(child).hasClass("page")

    pageNumber = 0
    while elements.length > 0
      console.log elements[elements.length - 1].text()

      page = $("<div></div>")
      page.addClass("page")
      $(el).append(page)
      page.attr "pageNumber", ++pageNumber

      lastEl = null
      while elements.length > 0 and page.innerHeight() >= page[0].scrollHeight
        lastEl = elements[0]
        page.append lastEl
        elements.shift()

      if page.innerHeight() < page[0].scrollHeight
        elements.unshift lastEl.detach()

  setTimeout((() =>
    splitIntoPages $("#script")
    $(".fountain-preview").css("background", "gray")
  ), 10)

  for preElement in $.merge(html.filter("pre"), html.find("pre"))
    codeBlock = $(preElement.firstChild)
    fenceName = codeBlock.attr('class')?.replace(/^lang-/, '') ? defaultLanguage

    highlighter ?= new Highlights(registry: atom.grammars)
    highlightedHtml = highlighter.highlightSync
      fileContents: codeBlock.text()
      scopeName: scopeForFenceName(fenceName)

    highlightedBlock = $(highlightedHtml)
    # The `editor` class messes things up as `.editor` has absolutely positioned lines
    highlightedBlock.removeClass('editor').addClass("lang-#{fenceName}")
    highlightedBlock.insertAfter(preElement)
    preElement.remove()

  html
