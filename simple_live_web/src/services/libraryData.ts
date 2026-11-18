// Compatibility exports keep existing page imports stable while ownership is split.
export type {
  Follow,
  History,
  Tag,
  Library,
  Room,
  Category,
  CategoryGroup,
  Selection,
  Archive,
} from "../types/library";
export { platforms } from "../app/platforms";
export { safeImage } from "./media";
export {
  emptyLibrary,
  validate,
  loadLibrary,
  saveLibrary,
  rawLibrary,
  resetLibrary,
} from "../stores/libraryStorage";
export {
  readArchive,
  restore,
  makeArchive,
  toBase64,
  fromBase64,
  download,
} from "../features/sync/archive";
export { api } from "./apiClient";
