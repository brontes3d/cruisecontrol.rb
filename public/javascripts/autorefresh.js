function AutoRefresh (type) {
}

AutoRefresh.getBuildRefresh = function() {
  return window._autorefresh != "false"
}

AutoRefresh.getUserRefresh = function() {
  return getCookie('ccrb.user.autorefresh') == "true"
}

AutoRefresh.setUserRefresh = function(setting) {
  return setCookie('ccrb.user.autorefresh', setting)
}

AutoRefresh.getStatus = function() {
  return "auto-refresh is " + (AutoRefresh.getUserRefresh() ? "on" : "off")
}

AutoRefresh.configure = function(element_id) {
  $(element_id).innerHTML= "<a id='autorefresh_toggle' href='#'>" + AutoRefresh.getStatus() + "</a>";
  console.log="suckit"
  $('autorefresh_toggle').observe('click', function(event) {
    AutoRefresh.setUserRefresh(!AutoRefresh.getUserRefresh())
    $('autorefresh_toggle').innerHTML=AutoRefresh.getStatus()
  })
}

AutoRefresh.doRefresh = function() {
  return AutoRefresh.getUserRefresh() && AutoRefresh.getBuildRefresh()
}
