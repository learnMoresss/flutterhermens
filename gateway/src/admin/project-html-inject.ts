import {
  buildHermesAppInjectComment,
  buildHermesAppSnippetsScript,
} from './hermes-app-snippets.js';

export function buildProjectHtmlInject(slug: string): string {
  const projectMeta = JSON.stringify({
    slug,
    apiBase: `/v1/projects/${slug}/api`,
    hostApi: '/v1/hermes-app/host.js',
    snippetsApi: '/v1/hermes-app/snippets.js',
  });
  return (
    buildHermesAppInjectComment() +
    `<script>window.__HERMES_PROJECT__=${projectMeta};</script>` +
    `<script src="/v1/hermes-app/host.js"></script>` +
    `<script>${buildHermesAppSnippetsScript()}</script>`
  );
}

export function injectProjectHtml(html: string, slug: string): string {
  const inject = buildProjectHtmlInject(slug);
  if (html.includes('</head>')) {
    return html.replace('</head>', `${inject}</head>`);
  }
  return inject + html;
}
