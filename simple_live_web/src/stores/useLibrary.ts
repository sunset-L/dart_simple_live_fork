import { useCallback, useEffect, useState } from "react";
import { loadLibrary, saveLibrary } from "./libraryStorage";
import type { Library } from "../types/library";
export function useLibrary() {
  const [data, setData] = useState(() => loadLibrary().data);
  useEffect(() => {
    const reload = () => setData(loadLibrary().data);
    window.addEventListener("storage", reload);
    window.addEventListener("simple-live-library", reload);
    return () => {
      window.removeEventListener("storage", reload);
      window.removeEventListener("simple-live-library", reload);
    };
  }, []);
  const update = useCallback((transform: (data: Library) => Library) => {
    const current = loadLibrary();
    if (current.error) throw new Error(current.error);
    const next = transform(current.data);
    saveLibrary(next);
    setData(next);
    window.dispatchEvent(new Event("simple-live-library"));
  }, []);
  return { data, update };
}
