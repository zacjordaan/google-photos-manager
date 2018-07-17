document.addEventListener('DOMContentLoaded', function() {
  
  var bgp = chrome.extension.getBackgroundPage();
  bgp.console.log('DOMContentLoaded');

  var checkPageButton = document.getElementById('checkPage');
  
  checkPageButton.addEventListener('click', function() {

    console.log('checkPageButton clicked');
    chrome.extension.getBackgroundPage().console.log('checkPageButton clicked');
    bgp.console.log('checkPageButton clicked');

    /*
    chrome.tabs.getSelected(null, function(tab) {
      d = document;

      var f = d.createElement('form');
      f.action = 'http://gtmetrix.com/analyze.html?bm';
      f.method = 'post';
      var i = d.createElement('input');
      i.type = 'hidden';
      i.name = 'url';
      i.value = tab.url;
      f.appendChild(i);
      d.body.appendChild(f);
      f.submit();
    });
    */

  }, false);

}, false);


//https://developer.chrome.com/apps/fileSystem