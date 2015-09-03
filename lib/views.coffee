{$, View, SelectListView} = require 'atom-space-pen-views'
Convert = require('ansi-to-html')
_ = require('lodash')

module.exports =
  StatusView:
    class StatusView extends View
      @content: ->
        @div class: 'xbuild-status inline-block', =>
          @a class: 'xbuild-status xbuild-label', outlet: 'build', 'build'
          @span class: 'xbuild-status xbuild-label', '{'
          @a class: 'xbuild-status xbuild-project', outlet: 'project'
          @span class: 'xbuild-status xbuild-label', ':'
          @a class: 'xbuild-status xbuild-target', outlet: 'target'
          @span class: 'xbuild-status xbuild-label', '}'

      initialize: ->
        @build.click(-> atom.commands.dispatch(
          atom.views.getView(atom.workspace), "xbuild:toggle"))

      onClick: (projectClick, targetClick) ->
        @project.click(projectClick)
        @target.click(targetClick)

      update: (project, target) ->
        @project.html(project)
        @target.html(target)

  SelectionView:
    class SelectionView extends SelectListView
      initialize: (items, selectedItem, @selectHandler, title) ->
        super
        @addClass('overlay from-top')
        @panel ?= atom.workspace.addModalPanel(item: this)
        @setItems(items)

        # select the specified item to begin with
        next = first = @getSelectedItem()
        while next != selectedItem
          @selectNextItemView()
          next = @getSelectedItem()
          if next == first
            break

        @panel.show()
        @focusFilterEditor()

      viewForItem: (item) ->
        "<li>#{item}</li>"

      confirmed: (item) ->
        @selectHandler(item)
        @panel.hide()  # destroy or hide??? who knows...
        # @panel.destroy()

      cancelled: (item) ->
        @panel.hide()  # destroy or hide??? who knows...
        # @panel.destroy()

  BuildView:
    class BuildView extends View
      @content: ->
        @div tabIndex: -1, class: 'build tool-panel panel-bottom native-key-bindings', =>
          @div class: 'btn-container pull-right', =>
            @button class: 'btn btn-default icon icon-chevron-up', outlet: 'monocleButton', click: 'toggleMonocle'
            @button class: 'btn btn-default icon icon-trashcan new-row', click: 'clear'
            @button class: 'btn btn-default icon icon-x', click: 'close'

          @div class: 'output panel-body', outlet: 'output'

          @div =>
            @h1 class: 'title panel-heading', outlet: 'title', =>
              @span class: 'build-timer', outlet: 'buildTimer', '0.0 s'
              @span class: 'title-text', outlet: 'titleText', 'Ready'

      initialize: () ->
        @titleLoop = ['Building', 'Building.', 'Building..', 'Building...']
        @titleLoop.rotate = () ->
          @n = @n || 0
          (++@n == 3) && @push(@shift()) && (@n = 0)
        @a2h = new Convert()
        @monocle = false
        @starttime = new Date()

      attach: ->
        @panel?.destroy()
        @panel = atom.workspace.addBottomPanel(item: this)
        @height = @output.offset().top + @output.height()
        @heightFromConfig()
        @focus()

      detach: ->
        atom.views.getView(atom.workspace)?.focus()
        @panel?.destroy()
        @panel = null

      isAttached: -> !!@panel
      close: -> @detach()
      toggle: -> if @isAttached() then @detach() else @attach()
      clear: ->
        @reset()
        @attach()

      heightFromConfig: ->
        @setHeightPercent(atom.config.get(
          if @monocle then 'build.monocleHeight' else 'build.minimizedHeight'))

      reset: ->
        clearTimeout(@titleTimer)
        @title.removeClass('success error warning')
        @output.empty()
        @titleText.text('Cleared.')
        @detach()

      updateTitle: ->
        @titleText.text(@titleLoop[0])
        @titleLoop.rotate()
        @buildTimer.text(((new Date() - @starttime)/1000).toFixed(1) + ' s')
        @titleTimer = setTimeout(@updateTitle.bind(this), 100)

      setHeightPercent: (percent) ->
        @output.css('height', (percent * @height) + 'px')

      toggleMonocle: ->
        if !@monocle
          @setHeightPercent(atom.config.get('build.monocleHeight'))
          @monocleButton.removeClass('icon-chevron-up').addClass('icon-chevron-down')
        else
          @setHeightPercent(atom.config.get('build.minimizedHeight'))
          @monocleButton.removeClass('icon-chevron-down').addClass('icon-chevron-up')
        @monocle = !@monocle

      buildStarted: ->
        @starttime = new Date()
        @reset()
        @attach()
        if atom.config.get('build.stealFocus')
          @focus()
        @updateTitle()

      buildFinished: (success) ->
        if not success
          force = atom.config.get('build.panelVisibility') == 'Show on Error'
          @attach(force)
        @titleText.text(if success then 'Build finished.' else 'Build failed.')
        @title.addClass(if success then 'success' else 'error')
        clearTimeout(@titleTimer)

      buildAbortInitiated: ->
        @titleText.text('Build process termination imminent...')
        clearTimeout(@titleTimer)
        @title.addClass('error')

      buildAborted: ->
        @titleText.text('Aborted!')

      append: (data) ->
        @output.append(@a2h.toHtml(_.escape(data)))
        @output.scrollTop(@output[0].scrollHeight)

      replace: (text, onclick) ->
        @output.empty()
        output = @a2h.toHtml(text)

        mapObj =
          PASS: '<span class="output-good">PASS</span>'
          FAIL: '<span class="output-bad">FAIL</span>'
          FAILED: '<span class="output-bad">FAILED</span>'
          "error:": '<span class="output-bad">error:</span>'
          "warning:": '<span class="output-ugly">warning:</span>'
          "note:": '<span class="output-ugly">note:</span>'
        output = output.replace(/\b(PASS|FAIL|FAILED)\b/g,
          (matched)-> mapObj[matched]).replace(/\b(error|warning|note):/g,
            (matched)-> mapObj[matched])

        @output.append(output)
        @output.find('a').on('click', ->
          onclick($(this).attr('id')))
        @output.scrollTop(@output[0].scrollHeight)

      scrollTo: (type, id) ->
        position = @output.find('.' + type + '#' + id).position()
        if position
          @output.scrollTop(position.top + @output.scrollTop())
