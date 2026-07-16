// SPDX-License-Identifier: MIT

/**
 * Real markup captured from an X longform Article (x.com/addyosmani/status/…),
 * trimmed to the parts that matter: paragraphs whose sentences are split into
 * Draft.js <span> runs, each outbound reference link wrapped in its own
 * block-level <div>, and a media <section> whose link is root-relative and wraps
 * an <img>. Obfuscated class names are kept verbatim — the adapter must not
 * depend on them, and this fixture proves it doesn't.
 */

const REF_WRAPPER_CLASS = "css-175oi2r r-1loqt21 r-1471scf r-o7ynqc r-6416eg r-1ny4l3l";
const LINK_CLASS =
  "css-146c3p1 r-bcqeeo r-1ttztb7 r-qvutc0 r-37j5jr r-1inkyih r-rjixqe r-16dba41 r-1ddef8g r-tjvw6i r-1loqt21";

/** A sentence broken into Draft.js runs, with a reference link mid-sentence. */
export const LOOPS_PARAGRAPH =
  `<div class="longform-unstyled" data-block="true" data-offset-key="4uknm-0-0">` +
  `<div data-offset-key="4uknm-0-0" class="public-DraftStyleDefault-block public-DraftStyleDefault-ltr">` +
  `<span data-offset-key="4uknm-0-0"><span data-text="true">In the past year, the conversation around </span></span>` +
  `<span data-offset-key="4uknm-0-1" style="font-weight: bold;"><span data-text="true">agentic engineering</span></span>` +
  `<span data-offset-key="4uknm-0-2"><span data-text="true"> has moved to </span></span>` +
  `<span data-offset-key="4uknm-0-3" style="font-weight: bold;"><span data-text="true">harnesses</span></span>` +
  `<span data-offset-key="4uknm-0-4"><span data-text="true"> and </span></span>` +
  `<div class="${REF_WRAPPER_CLASS}">` +
  `<a href="https://x.com/addyosmani/article/2064127981161959567?lang=en" dir="ltr" rel="noopener noreferrer nofollow" target="_blank" role="link" class="${LINK_CLASS}" style="color: rgb(15, 20, 25);">` +
  `<span data-offset-key="4uknm-1-0" style="font-weight: bold;"><span data-text="true">loops</span></span>` +
  `</a></div>` +
  `<span data-offset-key="4uknm-2-0"><span data-text="true">, </span></span>` +
  `<span data-offset-key="4uknm-2-1" style="font-weight: bold;"><span data-text="true">fleets</span></span>` +
  `<span data-offset-key="4uknm-2-2"><span data-text="true"> and </span></span>` +
  `<span data-offset-key="4uknm-2-3" style="font-weight: bold;"><span data-text="true">software factories</span></span>` +
  `<span data-offset-key="4uknm-2-4"><span data-text="true">. My 2c is engineers need to own the outer loop - the accountability for these systems.</span></span>` +
  `</div></div>`;

/** A reference link between two sentence runs, as the citation paragraphs do. */
export const SONAR_PARAGRAPH =
  `<div class="longform-unstyled" data-block="true" data-offset-key="bln5k-0-0">` +
  `<div data-offset-key="bln5k-0-0" class="public-DraftStyleDefault-block public-DraftStyleDefault-ltr">` +
  `<span data-offset-key="bln5k-0-0"><span data-text="true">The potential for AI code is no longer marginal. In a Sonar 2026 survey, we asked teams about the share of their commits that were AI-assisted. It was small but non-trivial. </span></span>` +
  `<div class="${REF_WRAPPER_CLASS}">` +
  `<a href="https://www.sonarsource.com/state-of-code-developer-survey-report.pdf" dir="ltr" rel="noopener noreferrer nofollow" target="_blank" role="link" class="${LINK_CLASS}" style="color: rgb(15, 20, 25);">` +
  `<span data-offset-key="bln5k-1-0"><span data-text="true">Sonar's 2026 State of Code report</span></span>` +
  `</a></div>` +
  `<span data-offset-key="bln5k-2-0"><span data-text="true"> found that 42% of committed code was AI-generated or significantly AI-assisted, with expectations for that share to keep growing rather than plateauing.</span></span>` +
  `</div></div>`;

/** A media block: root-relative link wrapping the article's image. */
export const MEDIA_SECTION =
  `<section class="" data-block="true" data-offset-key="9f5dc-0-0" contenteditable="false">` +
  `<div class="css-175oi2r r-1nxhmzv"><div class="css-175oi2r r-13qz1uu">` +
  `<a href="/addyosmani/article/2074927530482835916/media/2074681165248970753" role="link" class="css-175oi2r r-1pi2tsx r-1ny4l3l r-1loqt21">` +
  `<div aria-label="Image" class="css-175oi2r" data-testid="tweetPhoto">` +
  `<img alt="Image" draggable="true" src="https://pbs.twimg.com/media/HMq_hxTbwAEfRBE?format=jpg&amp;name=medium" class="css-9pa8cd">` +
  `</div></a></div></div></section>`;

/** Plain Draft.js prose, no links — bulk so Readability scores the article. */
export const PLAIN_PARAGRAPH =
  `<div class="longform-unstyled" data-block="true" data-offset-key="99bog-0-0">` +
  `<div data-offset-key="99bog-0-0" class="public-DraftStyleDefault-block public-DraftStyleDefault-ltr">` +
  `<span data-offset-key="99bog-0-0"><span data-text="true">Agents have leverage, and leverage creates obligations. Someone must be able to explain exactly what changed, why it was safe, and what will happen if they are wrong. Otherwise, their actions cannot be justified, which makes it unlikely their organization will ask for them in the first place.</span></span>` +
  `</div></div>`;

/** The captured article body, assembled the way the page nests it. */
export function xArticleFixture(): string {
  return (
    `<div data-contents="true">` +
    LOOPS_PARAGRAPH +
    MEDIA_SECTION +
    PLAIN_PARAGRAPH +
    PLAIN_PARAGRAPH +
    SONAR_PARAGRAPH +
    PLAIN_PARAGRAPH +
    PLAIN_PARAGRAPH +
    `</div>`
  );
}
