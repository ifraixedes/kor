kor.service "session_service", [
  "$http", "korData", "korFlash",
  (http, kd, kf) ->
    service = {
      is_guest: ->
        return false unless kd.info
        if user = kd.info.session.user
          user.name == 'guest'
        else
          false
      allowed_to: (policy, object) ->
        if kd.info && object
          collection_id = if angular.isObject(object)
            object.collection_id
          else
            object

          if kd.info.session.user.auth
            kd.info.session.user.auth.collections[policy] ||= []
            kd.info.session.user.auth.collections[policy].indexOf(collection_id) != -1
          else
            false
        else
          false
      allowed_to_any: (policy) ->
        if kd.info && kd.info.session.user.auth
          kd.info.session.user.auth.collections[policy].length != 0
        else
          false
      flash: (type, message) ->
        if kd.info
          kd.info.session.flash[type] = message
      reset_flash: ->
        if kd.info
          kd.info.session.flash = {}
      read_legacy_flash: ->
        if Settings.legacy_flash
          if message = Settings.legacy_flash.notice
            service.flash 'notice', message
          if message = Settings.legacy_flash.error
            service.flash 'error', message
          Settings.legacy_flash = {}
      in_clipboard: (entity) ->
        if kd.info && entity
          kd.info.session.clipboard ||= []
          kd.info.session.clipboard.indexOf(entity.id) != -1
        else
          false
      is_current: (entity) ->
        if kd.info && entity
          arr = kd.info.session.current_history
          arr[arr.length - 1].id == entity.id
        else
          false
      to_clipboard: (entity) ->
        id = if angular.isObject(entity) then entity.id else entity
        promise = http(
          method: "get"
          url: "/mark"
          headers: {accept: "application/json"}
          params: {id: id, mark: "mark"}
        )
        promise.success (data) -> 
          kd.info.session.clipboard = data.clipboard
          service.flash 'notice', data.message
      from_clipboard: (entity) ->
        id = if angular.isObject(entity) then entity.id else entity
        promise = http(
          method: "get"
          url: "/mark"
          headers: {accept: "application/json"}
          params: {id: id, mark: "unmark"}
        )
        promise.success (data) -> 
          kd.info.session.clipboard = data.clipboard
          service.flash 'notice', data.message
      to_current: (entity) ->
        promise = http(
          method: "get"
          url: "/mark_as_current/#{entity.id}"
          headers: {accept: "application/json"}
        )
        promise.success (data) ->
          kd.info.session.current_history = data.current_history
          service.flash 'notice', data.message
    }
]