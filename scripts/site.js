/**
 * Small site-level polish that does not belong to the theme package.
 * - Keeps the visible home hero to one title line while retaining the semantic h1.
 * - Replaces ShokaX's `alternate = title = subtitle` browser title with a cleaner one.
 * - Reserves the desktop sidebar height so a short page cannot enter the
 *   sidebar-affix <-> page-height feedback loop at the bottom (visible flashing).
 */

hexo.extend.injector.register(
  'head_end',
  `<style>
#brand .artboard + h1.title{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
#brand .logo + .meta{margin-top:1rem}
@media (min-width:991px){#sidebar{min-height:100vh}}
</style>`,
  'default'
);

hexo.extend.filter.register('after_render:html', function (str, data) {
  const page = data.page || {};
  const siteTitle = hexo.config.title;
  const subtitle = hexo.config.subtitle;

  let title;
  if (page.__index) {
    title = subtitle ? `${siteTitle} | ${subtitle}` : siteTitle;
  } else if (page.title && page.title !== siteTitle) {
    title = `${page.title} | ${siteTitle}`;
  } else {
    title = siteTitle;
  }

  const safe = String(title)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

  return str.replace(/<title>[\s\S]*?<\/title>/, `<title>${safe}</title>`);
});
