import { RE2JS } from "re2js";

const fortune =
  /福袋|天选|抽奖|中奖|开奖|奖品|奖励发放|恭喜.{0,12}(获得|抽中|抢到|中奖|中得)|(领取|领|抢|瓜分).{0,6}(福袋|红包|奖品|奖励|优惠券)|已参与|参与成功|参与抽奖|(发送|输入|回复).{0,4}口令|(免费|限时).{0,6}(领|抽|抢)/i;
export function createFilter(words: string[], blockFortune: boolean) {
  const patterns = words.map((word) => {
    if (!word.startsWith("/") || !word.endsWith("/") || word.length < 3)
      return word;
    try {
      return RE2JS.compile(word.slice(1, -1));
    } catch {
      return null;
    }
  });
  return (text: string) =>
    !(blockFortune && fortune.test(text)) &&
    !patterns.some((pattern) =>
      typeof pattern === "string"
        ? text.includes(pattern)
        : pattern?.test(text),
    );
}
