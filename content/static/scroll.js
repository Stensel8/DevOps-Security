// A sprinkle of Javascript to make the header translucent when the scroll position is not at the top of the page.
// (No, there's no security problem here.)
// Staat in een eigen bestand en niet meer in de HTML, dus er staat geen inline script meer in de pagina.
addEventListener('scroll', function() {
  if (scrollY > 0) document.body.classList.add('scrolled');
  else document.body.classList.remove('scrolled');
});
