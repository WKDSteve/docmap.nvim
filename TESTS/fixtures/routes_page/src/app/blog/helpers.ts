/** Turns a title into a slug. */
export function slugify(title: string): string {
  return title.toLowerCase().replace(/ /g, "-");
}
