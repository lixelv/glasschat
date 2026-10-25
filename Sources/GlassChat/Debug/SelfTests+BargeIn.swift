#if DEBUG
import Foundation

extension SelfTests {
    static func bargeIn() {
        expect(!BargeIn.isMeaningful(heard: "подожди стоп", voiced: 0.3, spoken: ""), "too little voice")
        expect(!BargeIn.isMeaningful(heard: "да", voiced: 0.8, spoken: ""), "one short word")
        expect(!BargeIn.isMeaningful(heard: "Thank you", voiced: 1, spoken: ""), "a noise phrase")
        expect(!BargeIn.isMeaningful(heard: "восемь градусов облачность", voiced: 1, spoken: "В Таллине восемь градусов, облачность"),
               "the assistant's own words (echo)")
        expect(BargeIn.isMeaningful(heard: "подожди, лучше про Париж", voiced: 0.9, spoken: "В Таллине восемь градусов"), "a real interruption")
        expect(BargeIn.isMeaningful(heard: "стоп", voiced: 0.6, spoken: ""), "one clear word")
    }
}
#endif
