#
# Copyright (C) 2011 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

# also requires
# jquery.formSubmit
# jqueryui dialog
# jquery disableWhileLoading

define [
  'i18n!help_dialog'
  'jst/helpDialog'
  'jquery'
  'underscore'
  'INST'
  'str/htmlEscape'
  'compiled/fn/preventDefault'

  'jquery.instructure_misc_helpers'
  'jqueryui/dialog'
  'jquery.disableWhileLoading'
], (I18n, helpDialogTemplate, $, _, INST, htmlEscape, preventDefault) ->

  helpDialog =
    defaultTitle: I18n.t 'Help', "Help"

    showEmail: -> not ENV.current_user_id

    animateDuration: 100

    initDialog: ->
      @defaultTitle = ENV.help_link_name || @defaultTitle
      @$dialog = $('<div style="padding:0; overflow: visible;" />').dialog
        resizable: false
        width: 400
        title: @defaultTitle
        close: => @switchTo('#help-dialog-options')

      @$dialog.dialog('widget').delegate 'a[href="#teacher_feedback"],
                                          a[href="#create_ticket"],
                                          a[href="#help-dialog-options"]', 'click', preventDefault ({currentTarget}) =>
        @switchTo $(currentTarget).attr('href')

      @helpLinksDfd = $.getJSON('/help_links').done (links) =>
        # only show the links that are available to the roles of this user
        links = $.grep links, (link) ->
          _.detect link.available_to, (role) ->
            role is 'user' or
            (ENV.current_user_roles and role in ENV.current_user_roles)
        locals =
          showEmail: @showEmail()
          helpLinks: links
          url: window.location
          contextAssetString: ENV.context_asset_string
          userRoles: ENV.current_user_roles

        @$dialog.html(helpDialogTemplate locals)
        @initTicketForm()

        # recenter the dialog once all the links have been loaded so it is back in the
        # middle of the page
        @$dialog?.dialog('option', 'position', 'center')

        $(this).trigger('ready')
      @$dialog.disableWhileLoading @helpLinksDfd
      @dialogInited = true

    initTicketForm: ->
      requiredFields = ['error[subject]', 'error[comments]', 'error[user_perceived_severity]']
      requiredFields.push 'error[email]' if @showEmail()

      $form = @$dialog.find('#create_ticket').formSubmit
        disableWhileLoading: true
        required: requiredFields
        success: =>
          @$dialog.dialog('close')
          $form.find(':input').val('')

    switchTo: (panelId) ->
      toggleablePanels = "#teacher_feedback, #create_ticket"
      homePanel = "#help-dialog-options"
      @$dialog.find(toggleablePanels).hide()
      newPanel = @$dialog.find(panelId)
      newHeight = newPanel.show().outerHeight()
      @$dialog.animate({
        left : if toggleablePanels.match(panelId) then -400 else 0
        height: newHeight
      }, {
        step: =>
          #reposition vertically to reflect current height
          @initDialog() unless @dialogInited and @$dialog?.hasClass("ui-dialog-content")
          @$dialog?.dialog('option', 'position', 'center')
        duration: @animateDuration
        complete: ->
          toFocus = newPanel.find(':input').not(':disabled')
          if toFocus.length is 0
            toFocus = newPanel.find(':focusable')
          toFocus.first().focus()
          $(homePanel).hide() unless panelId is homePanel
      })

      if newTitle = @$dialog.find("a[href='#{panelId}'] .text").text()
        newTitle = $("
          <a class='ui-dialog-header-backlink' href='#help-dialog-options'>
            #{htmlEscape(I18n.t('Back', 'Back'))}
          </a>
          <span>#{htmlEscape(newTitle)}</span>
        ")
      else
        newTitle = @defaultTitle
      @$dialog.dialog 'option', 'title', newTitle

    open: ->
      helpDialog.initDialog() unless helpDialog.dialogInited and helpDialog.$dialog?.hasClass("ui-dialog-content")
      helpDialog.$dialog.dialog('open')
      helpDialog.initTeacherFeedback()

    initTeacherFeedback: ->
      currentUserIsStudent = ENV.current_user_roles and 'student' in ENV.current_user_roles
      if !@teacherFeedbackInited and currentUserIsStudent
        @teacherFeedbackInited = true
        coursesDfd = $.getJSON '/api/v1/courses.json'
        $form = null
        @helpLinksDfd.done =>
          $form = @$dialog.find("#teacher_feedback")
            .disableWhileLoading(coursesDfd)
            .formSubmit
              disableWhileLoading: true
              required: ['recipients[]', 'body']
              success: =>
                @$dialog.dialog('close')

        $.when(coursesDfd, @helpLinksDfd).done ([courses]) ->
          optionsHtml = $.map(courses, (c) ->
            "<option value='course_#{c.id}_admins' #{$.raw if ENV.context_id is c.id then 'selected' else ''}>
              #{htmlEscape(c.name)}
            </option>"
          ).join('')
          $form.find('[name="recipients[]"]').html(optionsHtml)

    initTriggers: ->
      $('.help_dialog_trigger').click preventDefault @open

