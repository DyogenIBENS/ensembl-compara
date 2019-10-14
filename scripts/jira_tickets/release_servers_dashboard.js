// https://stackoverflow.com/a/25359264
$.urlParam = function(name){
    var results = new RegExp('[\?&]' + name + '=([^&#]*)').exec(window.location.href);
    if (results==null) {
        return null;
    }
    return decodeURI(results[1]) || 0;
}

// https://stackoverflow.com/a/3291856
String.prototype.capitalize = function() {
    return this.charAt(0).toUpperCase() + this.slice(1);
}

// fetch ticket status from REST API
var endpoint_ticket_list = 'https://www.ebi.ac.uk/panda/jira/rest/api/2/search/?jql=project=ENSCOMPARASW+AND+issuetype=Sub-task+AND+fixVersion="Ensembl+__RELEASE__"+AND+(description~"cp__SERVER__*"+OR+description~"prod-__SERVER__*")+AND+status="In+progress"+ORDER+BY+created+ASC,id+ASC&maxResults=500';
var endpoint_ticket_query = 'https://www.ebi.ac.uk/panda/jira/rest/api/2/issue';
var url_jira_issue = 'https://www.ebi.ac.uk/panda/jira/browse/';
var release = $.urlParam("release");

$('body').append('<h1>Release ' + release + ' - Server usage dashboard</h1>');

function process_server(server) { return function(json) {
    var n_tickets = json.issues.length;
    var table = $('<table class="server_dashboard"></table>').appendTo('#cp' + server);
    table.append('<tbody><tr id="usage_cp' + server + '"><th>mysql-ens-compara-prod-' + server + '</th></tr>');
    if (n_tickets) {
        $('#usage_cp' + server).append('<td><div class="status_bar"><div class="yellow_light" style="width:100%"><i>busy</i></div></div></td>');
        var ticket =json.issues[0];
        var summary = ticket.fields.summary;
        var division = ticket.fields.customfield_11130.value;
        var asignee = ticket.fields.assignee.name;
        $('#usage_cp' + server).append('<td class="ticket_summary">' + summary + ' for ' + division + ' (<i>' + asignee + '</i>)</td>');
        for (var i = 1; i < n_tickets; i++) {
            var ticket =json.issues[i];
            var summary = ticket.fields.summary;
            var asignee = ticket.fields.assignee.name;
            table.append('<tr><th></th><td></td><td class="ticket_summary">' + summary + ' for ' + division + ' (<i>' + asignee + '</i>)</td></tr>');
        }
    } else {
        $('#usage_cp' + server).append('<td><div class="status_bar"><div class="green_light" style="width:100%"><i>free</i></div></div></td><td class="ticket_summary"></td>');
    }
    table.append('</tbody>');
} }

for(var j = 1; j < 9; j++){
    var endpoint = endpoint_ticket_list.replace('__RELEASE__', release).replace(/__SERVER__/g, j);
    console.log(endpoint);
    $('body').append('<div id="cp' + j + '"></div>');
    $.ajax(endpoint, {
        success: process_server(j),
        error: function(jqXHR, status, error) {
            console.log('Error: ' + (error || jqXHR.crossDomain && 'Cross-Origin Request Blocked' || 'Network issues'));
            window.alert('Having trouble contacting Jira - please check that you are logged in');
        },
        crossDomain: true,
    })
}