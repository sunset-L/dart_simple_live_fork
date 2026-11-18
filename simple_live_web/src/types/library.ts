export interface Follow {
  id: string;
  roomId: string;
  siteId: string;
  userName: string;
  face: string;
  addTime: string;
  tag: string;
}

export interface History extends Omit<Follow, "addTime" | "tag"> {
  updateTime: string;
}

export interface Tag {
  id: string;
  tag: string;
  userId: string[];
}

export interface Library {
  follows: Follow[];
  histories: History[];
  tags: Tag[];
  blocked: string[];
}

export interface Room {
  roomId: string;
  siteId: string;
  title: string;
  cover: string;
  userName: string;
  online: number;
}

export interface Category {
  id: string;
  parentId: string;
  name: string;
  pic: string | null;
}

export interface CategoryGroup {
  id: string;
  name: string;
  children: Category[];
}

export type Selection = {
  follows: boolean;
  histories: boolean;
  blocked: boolean;
};

export type Archive = Record<string, Uint8Array>;
