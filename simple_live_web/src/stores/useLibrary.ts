import { useCallback, useEffect, useState } from "react";
import { loadLibrary, saveLibrary, watchLibrary } from "./libraryStorage";
import type { Library } from "../types/library";
export function useLibrary() {
  const [data, setData] = useState(() => loadLibrary().data);
  useEffect(() => {
    const reload = () => setData(loadLibrary().data);
    return watchLibrary(reload);
  }, []);
  const update = useCallback(async (transform: (data: Library) => Library) => {
    const current = loadLibrary();
    if (current.error) throw new Error(current.error);
    const next = transform(current.data);
    await saveLibrary(next);
  }, []);
  return { data, update };
}
