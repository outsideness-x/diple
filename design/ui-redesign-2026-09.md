# diple — UI/UX аудит и план правок

**Дата:** 2026-09-02
**Ориентиры:** Matter, Readwise Reader. Целевой регистр — дорогое независимое издательство:
минимализм, типографика, ни одной лишней плашки.
**Метод:** прочитан весь слой `Theme/` и `View/`, приложение проведено на симуляторе
(`OROT-iPhone17`, iOS 26.3) по всем четырём вкладкам, в читалке и в обеих темах.

---

## 0. Что уже сделано хорошо — не трогать

Это не вежливость, это граница работ. Ломать перечисленное запрещено.

| Что | Почему это уже уровень ориентира |
|---|---|
| `Theme/DipleColor`, `DipleType`, `DipleSpace`, `DipleMotion` | Токен-слой с записанным обоснованием каждого значения. Такого нет ни у Matter, ни у Readwise. |
| Плавающие бары читалки (`ReaderBarBackground`) | Страница продолжается под стеклом, а не обрезается плитой. Лучше, чем у Readwise. |
| `ReaderChrome.forTheme` | Хром берёт тон у страницы, а не спорит с ней. |
| Свотчи тем в `ReaderSettingsView` | Каждая тема нарисована своей бумагой и своими чернилами. Лучший контрол в приложении. |
| `LibraryRowView` / `NoteCardView.row` | Линейка одновременно разделитель и прогресс. Настоящая каталожная вёрстка. |
| `DipleCoverArt` | Стабильный цвет обложки из хеша заголовка. Полка узнаётся. |
| `SelectionSettle`, `ReadingTrailPill`, Living Margins, Second Read | Продуктовые идеи, которых нет у конкурентов. |

---

## 1. Диагноз

**Атомарный дизайн — отличный. Композиционный — слабый.**

Каждый токен и каждый компонент по отдельности сделаны правильно и с обоснованием.
Ломается всё на уровне *страницы*: как компоненты стоят друг относительно друга, сколько
экрана занимает управление и сколько — содержимое, и одним ли голосом всё это говорит.

Пять системных дефектов, в порядке ущерба:

### Д1. Хрома больше, чем содержимого

Замерено на симуляторе (экран 402 × 874 pt):

| Экран | Первый пиксель содержимого | Доля экрана под управление |
|---|---|---|
| Library | **326 pt** | **37 %** |
| Notes | 294 pt | 34 % |
| Home | 258 pt | 30 % |

Library до первой обложки показывает **пять рядов управления**: навбар → поле поиска →
сегментированный контрол → чипы типа → заголовок полки с двумя контролами. Комментарий в
`LibraryView.swift:441` честно описывает, как из экрана убрали hero, потому что «читатель
встречал пять рядов контролов… почти половину дисплея». Hero убрали — пять рядов остались.

У Matter и Readwise содержимое начинается в первые 15 % экрана. Это главное, что отделяет
diple от «премиального».

### Д2. Акцент работает заливкой, а не светом

Собственная документация `DipleColor.accentGlow` говорит: *«Цветом управляют свечением, а не
насыщенными заливками»*. Фактически акцент залит в ~15 местах. На одном экране Settings
одновременно: залитая кнопка «Dark», кольцо на «Brass», залитая «Medium» и два латунных
тумблера — **пять одинаково громких объектов**, и ни один из них не является главным
действием экрана.

### Д3. Нет бумаги

Для регистра «издательство» интерфейс должен ощущаться печатным объектом. Сейчас:
тёмно-серое на тёмно-сером (dark) или серое на сером (light). Белой/кремовой бумаги нет
нигде, кроме самой страницы читалки. Светлая тема (`canvas = #F4F4F7`, холодный) читается
заметно дешевле тёмной — ровно то «неоформленная форма», от чего `DipleColor` открещивается
в своём же комментарии.

### Д4. Один шрифт на всё

Всё — San Francisco. Решение принято сознательно (New York тёк в карточки цитат и не имел
хангыля), и это было правильно **как аварийная мера**. Но следствие: приложение читается как
«хорошо сделанное приложение», а не как «издание». У издательства есть голос в шрифте.

Важно: причина, по которой New York выкинули из UI, — **это была проблема CSS-каскада внутри
веб-вью читалки**, где ключевое слово `-apple-system` съедало весь каскад. В SwiftUI `Text`
такой проблемы нет: CoreText делает поглифовый фолбэк, что уже подтверждено на практике —
`Caveat` не имеет хангыля, и корейская заметка спокойно падает в системный санс
(зафиксировано в памяти проекта как «не регрессия»).

### Д5. Четыре языка «выбранного состояния»

| Место | Как показан выбор |
|---|---|
| `ReaderSettingsView.themeButton` | обводка акцентом 2 pt |
| `ReaderSettingsView.fontFamilyButton` | сплошная заливка акцентом |
| `AppSettingsView` accent swatch | белое кольцо + галочка |
| `DipleTabBar` | капсула `accentSoft` |
| чипы фильтров (3 экрана) | сплошная заливка акцентом |

---

## 2. Правки

Порядок = приоритет. Каждая правка самостоятельна и коммитится отдельно.

---

### P1. Светлая тема: акцент нечитаем как текст — **это баг, а не вкусовщина**

**Проблема.** Все пять акцентов проваливают контраст как цвет текста на светлом холсте.
Посчитано по WCAG относительно `#FFFFFF`:

| Акцент | Hex | Контраст на белом | Норма 4.5:1 |
|---|---|---|---|
| Mint | `#6FD6B4` | **1.76 : 1** | ✗ |
| Periwinkle | `#8FA4F2` | **2.40 : 1** | ✗ |
| Lilac | `#DF9BE1` | **2.12 : 1** | ✗ |
| Brass (дефолт) | `#C8A45C` | **2.35 : 1** | ✗ |
| Clay | `#D97757` | **3.11 : 1** | ✗ (проходит только 3:1 для крупного) |

На тёмном холсте `#0B0B0F` brass даёт 8.0 : 1 — там всё в порядке. То есть дефект ровно в
светлой теме, которая шипнута.

**Где горит.** Всё, где акцент — это `foregroundStyle`, а не фон:
`LibraryView.noResults` («Clear Search and Filters»), `LibraryView` toolbar `+`,
`LibraryView.emptyLocation` иконка, `NotesView` «CONTINUE THINKING», `NotesView.noResults`,
`NoteCardView.card` иконка, `TagChipView` (kind `.book`), `ReaderContainerView` процент в
нижнем баре, `HubView`/`SecondReadView` пустые состояния.

**Решение.** Добавить в `DipleAccent` вторую точку — «чернила акцента», затемнённый вариант
для использования как текст, и сделать токен динамическим.

```swift
// Theme/DipleAccent.swift
public extension DipleAccent {
    /// Тот же цвет, затемнённый до читаемости как текст на светлой бумаге.
    /// Проверено на 4.5:1 против `DipleColor.canvas` в светлой теме.
    /// Тёмная тема берёт `hex` без изменений — там он даёт 8:1 и затемнение убило бы его.
    var inkHex: String {
        switch self {
        case .lilac:      return "#8E4E90"
        case .mint:       return "#1F7A5C"
        case .clay:       return "#A34A2A"
        case .periwinkle: return "#4257B2"
        case .brass:      return "#8A6D2F"
        }
    }
}
```

```swift
// Theme/DipleColor.swift — рядом с accent/accentSoft/accentGlow
/// Акцент, пригодный как ЦВЕТ ТЕКСТА. Единственный акцентный токен, который разрешено
/// класть в `foregroundStyle` для чего-либо мельче 24 pt.
/// `accent` остаётся для заливок и для крупных знаков, где контраст обеспечивает `textOnAccent`.
public static var accentInk: Color {
    adaptive(
        light: UIColor(Color(hex: DipleAccent.current.inkHex)),
        dark:  UIColor(DipleAccent.current.color)
    )
}
```

> ⚠️ `DipleAccent.current` — `@MainActor` изменяемое состояние, поэтому `accentInk` должен
> быть `static var` (вычисляемый), а не `static let`, точно как существующий `accent`.
> Комментарий на `DipleColor.accent` объясняет почему — не повторять ошибку.

**Реализация.** Заменить `DipleColor.accent` → `DipleColor.accentInk` **только** там, где
он попадает в `foregroundStyle`/`.tint` текста и мелких глифов. Заливки (`background`,
`fill`, `in: Capsule()`) не трогать. Список файлов:
`LibraryView.swift`, `NotesView.swift`, `NoteCardView.swift`, `HubView.swift`,
`GlobalSearchView.swift`, `SecondReadView.swift`, `SourceOverviewView.swift`,
`BookOutlineSheetView.swift`, `ReaderContainerView.swift` (процент — см. P8).

**Проверка.** Переключить Settings → Appearance → Light и пройти Library → Notes → Search.
Ни одной латунной надписи на светлом фоне не должно остаться.

---

### P2. Единая архитектура страницы: `DipleMasthead`

**Проблема.** Три «места» (Home / Library / Notes) устроены тремя разными способами:

- Home: собственный масthead в контенте, навбар скрыт.
- Library: системный навбар, в заголовке — **вордмарк `diple.`**.
- Notes: системный навбар с заголовком `Notes` + отдельная плашка `CONTINUE THINKING`.

Вордмарк в навбаре Library — ровно тот антипаттерн, который осуждает комментарий
`HomeView.masthead`: *«вордмарк, сжатый до размера кнопки „назад“»*. Он там всё ещё есть.
И он ничего не сообщает: читатель и так знает, что он в diple; он не знает, что он в Library.

**Решение.** Один компонент, три вкладки, никаких системных навбаров на корнях.

```swift
// View/DipleMasthead.swift  (новый файл)

/// Шапка «места». Одна на Home, Library и Notes — три корня приложения обязаны
/// открываться одинаково, иначе переход между вкладками читается как переход между
/// приложениями.
///
/// Вордмарк живёт ровно в одном месте — на Home, — потому что название издания печатают
/// на первой полосе, а не на каждой. Остальные вкладки печатают своё имя.
public struct DipleMasthead<Trailing: View>: View {
    let title: String
    /// Строка под именем: дата на Home, счёт на Library, счёт на Notes.
    /// `nil` — строки нет, высота не резервируется.
    let strapline: String?
    /// Ставится в `.hero` только для вордмарка. Остальные — `.display`.
    let isWordmark: Bool
    @ViewBuilder let trailing: () -> Trailing

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(title)
                    .dipleType(isWordmark ? .wordmark : .hero)   // см. P3
                    .foregroundStyle(DipleColor.textPrimary)

                if let strapline {
                    Text(strapline)
                        .dipleType(.footnote, weight: .regular)
                        .foregroundStyle(DipleColor.textTertiary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: DipleSpace.m)
            trailing()
        }
        .padding(.horizontal, DipleSpace.xl)
        .padding(.top, DipleSpace.l)
    }
}
```

**Применение:**

| Экран | `title` | `strapline` | `trailing` |
|---|---|---|---|
| Home | `diple.` (`isWordmark`) | `Wednesday, 2 September` | `+` меню, шестерня |
| Library | `Library` | `12 sources · 3 unread` | `+` меню, шестерня |
| Notes | `Notes` | `48 notes` | `+`, сортировка |

**Обязательно вместе с этим:**
- `LibraryView`: убрать `.navigationTitle("diple.")` → `.toolbar(.hidden, for: .navigationBar)`,
  контролы из тулбара переезжают в `trailing`.
- `NotesView`: то же, и **удалить блок `workspaceHeader` («CONTINUE THINKING») целиком** —
  он ничего не озаглавливает (под ним закреплённая плашка поиска, а не список) и тратит
  акцент на ярлык без функции.
- `NavigationStack` сохраняется: `.navigationTitle` остаётся установленным (он подписывает
  кнопку «назад» на push-экранах), скрывается только сам бар — как уже сделано в `HomeView`.

**Риск.** У Library и Notes сейчас `.searchable` и `Menu` в тулбаре. При скрытии бара их надо
перенести руками; `.searchable` заменяется на инлайновое поле (см. P4).

---

### P3. Издательский голос: вторая гарнитура, ровно в пяти местах

**Проблема (Д4).** Приложение говорит системным голосом.

**Решение.** Ввести **одну** засечную гарнитуру и разрешить её **перечислимым списком мест**.
Не «серифом для контента» — это уже пробовали и получили утечку в шесть экранов. Пять
конкретных ролей, каждая заведена в `DipleType` явно.

**Гарнитура: Literata** (SIL OFL 1.1, переменный TTF, Google Fonts).
Причины: рисована TypeTogether для Google Play Books — то есть буквально издательская
читальная гарнитура; полная кириллица; крупный x-height, держит мелкий кегль; переменная —
один файл вместо четырёх. Альтернатива, если Literata покажется слишком «тёплой»:
**Source Serif 4** (OFL, Adobe, суше и строже). **Instrument Serif отклонён** — нет кириллицы.

Хангыля в Literata нет — и это нормально: SwiftUI сделает поглифовый фолбэк на Apple SD
Gothic Neo, ровно как уже происходит с `Caveat` (см. память проекта: «это не регрессия»).
**Именно поэтому серифом набираются только заголовки и цитаты, а не интерфейсные подписи** —
в короткой строке смешение гарнитур незаметно, в списке подписей было бы заметно.

**1. Установка.**
- Файл: `diple/Resources/Fonts/Literata-Variable.ttf` (+ `Literata-Italic-Variable.ttf`).
- `diple/Info.plist` → `UIAppFonts`: добавить обе строки (рядом с `Caveat-Variable.ttf`).
- Текст лицензии OFL положить туда же, где лежат OFL для Atkinson/OpenDyslexic — аудит
  App Store уже проверял, что они шипятся.

**2. Роли в `DipleType`.** Расширить `DipleTextStyle` третьим измерением — семейством:

```swift
public enum DipleFontFamily: Sendable {
    case system            // San Francisco — всё, что не перечислено ниже
    case editorial         // Literata

    func font(size: CGFloat, weight: Font.Weight, design: Font.Design) -> Font {
        switch self {
        case .system:    return .system(size: size, weight: weight, design: design)
        case .editorial: return .custom("Literata", size: size).weight(weight)
        }
    }
}
```

> ⚠️ `Font.custom(_:size:)` **не** масштабируется под Dynamic Type. Размер уже прогнан через
> `UIFontMetrics` в `scaledSize(for:)`, поэтому голая форма здесь корректна — но она корректна
> **только** потому, что вход уже масштабирован. Не заменять на `.custom(_:size:relativeTo:)`:
> получится двойное масштабирование.

Новые роли (добавить в `DipleTextStyle`, не менять существующие):

```swift
/// 34 — вордмарк на первой полосе. Единственное место, где он набирается.
public static let wordmark = DipleTextStyle(
    size: 34, weight: .regular, family: .editorial,
    metrics: .largeTitle, trackingRatio: -0.02)

/// 26 — заголовок ведущего материала (`SourceLeadView`).
public static let editorialLead = DipleTextStyle(
    size: 26, weight: .medium, family: .editorial,
    metrics: .title, trackingRatio: -0.015)

/// 19 — сохранённый пассаж, набранный как выносная цитата.
/// Заменяет `readingQuote` в карточках цитат.
public static let editorialQuote = DipleTextStyle(
    size: 19, weight: .regular, family: .editorial,
    metrics: .body, trackingRatio: 0)

/// 24 — заголовок заметки в редакторе.
public static let editorialNoteTitle = DipleTextStyle(
    size: 24, weight: .medium, family: .editorial,
    metrics: .title2, trackingRatio: -0.012)

/// 20 — заголовок пустого состояния и колофона. Единственное место, где серифом
/// набирается интерфейсный текст, и только потому, что он там один на экране.
public static let editorialTitle = DipleTextStyle(
    size: 20, weight: .medium, family: .editorial,
    metrics: .title3, trackingRatio: -0.01)
```

**3. Точки применения — исчерпывающий список. Больше нигде.**

| Файл | Что меняется |
|---|---|
| `HomeView.masthead` | `.hero` → `.wordmark` |
| `SourceLeadView` (заголовок) | `.display` → `.editorialLead` |
| `QuoteCardView` (текст цитаты) | `.readingBody` → `.editorialQuote` |
| `DailyResurfacingCard` (текст цитаты) | → `.editorialQuote` |
| `HighlightEditorView` (текст пассажа) | → `.editorialQuote` |
| `NoteDetailView` / `NoteEditorView` (заголовок) | `.noteTitle` → `.editorialNoteTitle` |
| `FinishedColophonView` (заголовок) | → `.editorialTitle` |
| `EmptyLibraryView`, `NotesView.emptyState`, `HubView.emptyState` | `.title` → `.editorialTitle` |

**Тело заметки остаётся SF.** Заметка — это то, что пишет читатель, а не то, что издано;
и в неё чаще всего попадает смесь языков.

**Проверка.** Открыть `#Preview("Type scale")` в `DipleType.swift` — добавить туда секцию
`EDITORIAL` со строкой `«Пиранези» · 책을 읽는 사람 · Specimen`, убедиться, что кириллица
идёт Literata, а хангыль спокойно падает в системный шрифт без тофу.

---

### P4. Library: пять рядов хрома → два

**Цель:** первая обложка на **≈190 pt** вместо 326 pt.

**4.1. Сегментированный контрол → типографический переключатель.**

`Picker(.segmented)` — единственный системный UIKit-контрол на экране, и он выглядит как
чужой. Заменить на три слова в строку: выбранное — `textPrimary` с акцентной линейкой под
ним, остальные — `textQuaternary`. Счёт — верхним индексом `.tag`, а не в скобках.

```swift
// View/LibraryLocationSwitch.swift (новый)
//
// Место — это раздел издания, а не переключатель режима. Раздел объявляют шрифтом:
// имя текущего набрано в полную силу, соседние приглушены, под текущим — линейка.
// Сегментированный контрол говорил «настройка», а не «раздел», и был единственным
// системным контролом на экране.
private func segment(_ location: BookLocation) -> some View {
    let isSelected = location == selection
    return Button { select(location) } label: {
        HStack(alignment: .top, spacing: DipleSpace.hair) {
            Text(location.title)
                .dipleType(.headline, weight: isSelected ? .semibold : .regular)
            let count = counts[location] ?? 0
            if count > 0 {
                Text("\(count)")
                    .dipleType(.tag)
                    .monospacedDigit()
                    .baselineOffset(6)
            }
        }
        .foregroundStyle(isSelected ? DipleColor.textPrimary : DipleColor.textQuaternary)
        .padding(.vertical, DipleSpace.s)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isSelected ? DipleColor.accent : .clear)
                .frame(height: 2)
        }
    }
    .buttonStyle(.readerControl)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
}
```
Расположение: `HStack(spacing: DipleSpace.xl)` + `Spacer()`, прижато влево — как рубрикатор
газеты, а не как контрол во всю ширину.

**4.2. Чипы типа (All / Books / PDFs / Articles) — убрать со страницы.**

Тип источника — низкочастотный фильтр. Он переезжает в существующий `filterMenu` отдельной
`Picker`-секцией рядом со Status и Sort. Ряд чипов исчезает.

Условие показа `viewModel.books.count > 1` заменить не нужно — ряда больше нет.

**4.3. Ряд тегов — тоже в меню.**

Секция меню с множественным выбором (`Toggle` на каждый тег). Метка `filterMenu` уже умеет
показывать активный фильтр — расширить её: если выбраны теги, печатать `#tag` или `n tags`.

**4.4. Поиск — инлайновое поле, одинаковое с Notes.**

Сейчас Library использует `.searchable`, а Notes — собственный `TextField`. Два языка поиска
в одном приложении. Унифицировать **на собственном поле** (`.searchable` даёт системный хром,
который нельзя привести к материалу приложения), вынести в общий компонент:

```swift
// View/DipleSearchField.swift (новый) — из NotesView.controls, дословно
public struct DipleSearchField: View {
    @Binding var text: String
    let prompt: String
    ...
}
```
и поставить в обоих экранах **под** заголовком полки, а не над ним — поле поиска не должно
стоять выше того, что оно ищет.

**Итоговая раскладка Library:**

```
[MASTHEAD]   Library                          [+] [⚙]
             12 sources · 3 unread
[РУБРИКАТОР] Inbox² · Later¹ · Archive
             ──────
[ЗАГОЛОВОК]  INBOX          2   [▦] [⇅ Recent]
[КОНТЕНТ]    ...
```

**Риск.** `listBrowser` — настоящий `List` (нужен для `swipeActions`), и `browseControls`
живут внутри него строками. При сокращении не сломать `.listRowInsets` — вертикальные
инсеты у строк книг обязаны остаться нулевыми, иначе линейки перестанут стыковаться.

---

### P5. Notes: снять плиту

**Проблема.** Закреплённая полоса контролов (`NotesView.controls`) нарисована
`.background(.ultraThinMaterial).background(DipleColor.canvas.opacity(0.88))` и на экране
читается **видимой серой плитой** с жёсткой горизонтальной границей поперёк страницы. Это
ровно та «плита», которую отвергает документация `ReaderBarBackground`.

**Решение.**
1. Удалить `workspaceHeader` («CONTINUE THINKING») — см. P2.
2. Полосу не пинить материалом. Оставить `pinnedViews: [.sectionHeaders]`, но фон заменить
   на `DipleColor.canvas` + хайрлайн снизу:

```swift
.background(DipleColor.canvas)
.overlay(alignment: .bottom) {
    Rectangle().fill(DipleColor.hairline).frame(height: DipleStroke.hairline)
}
```
   Материал оправдан, только когда под ним есть что показывать (бары читалки над страницей).
   Над списком заметок под ним канвас — то есть материал размывает пустоту и платит за это
   видимым швом.
3. Кнопка переключения раскладки (`rectangle.grid.1x2` / `square.grid.2x2`) переезжает в
   заголовок секции рядом со счётчиком — как `layoutToggle` в Library. Сейчас она стоит
   рядом с полем поиска, где читается как часть поиска.

---

### P6. Home: убрать три кнопки, дать странице низ

**6.1. Три кнопки захвата → одно меню в масthead.**

`quickCapture` занимает второй по ценности пояс экрана тремя утилитарными прямоугольниками
равного веса. Library уже имеет ровно это меню под `+` в тулбаре — дублировать его тремя
кнопками на первой полосе не нужно.

Заменить на `+` в `trailing` у `DipleMasthead` с тем же меню (`Save a Link` / `Import a File` /
`New Note`). Экономия ≈ 90 pt, минус три конкурирующих прямоугольника.

> Возражение «захват — ключевая привычка» учтено: действие не исчезает, оно переезжает в
> постоянно доступный `+`, который и так есть на соседней вкладке. Одно место вместо двух.

**6.2. Низ страницы.**

Все три вкладки заканчиваются пустотой на две трети экрана (видно на скриншотах). У издания
есть концовка. Добавить тихий колофон страницы — одну строку `.micro` / `textQuaternary`
в самом низу скролла, когда содержимое короче экрана:

```swift
// View/DipleFoot.swift
// Концовка полосы. Не «статистика» и не геймификация — одна строка выходных данных,
// как в конце книги. Печатается только когда странице иначе нечем закончиться.
Text("\(sources) sources · \(passages) passages · \(notes) notes")
```
Ставится на Home, Library и Notes. Никаких стриков, бейджей и медалей.

---

### P7. Один язык выбранного состояния

**Правило (записать в `DipleColor` рядом с `accentGlow`):**

> Акцент заливается **ровно в одном объекте на экран** — в главном действии. Всякий другой
> выбор помечается обводкой либо `accentSoft`, но не заливкой. Экран с пятью залитыми
> объектами не имеет главного.

Один модификатор на всё приложение:

```swift
// Theme/DipleSurface.swift
public extension View {
    /// Помечает элемент как выбранный. Единственный разрешённый способ.
    /// Обводка, а не заливка: заливка забирает у экрана главное действие, а выбранный
    /// фильтр — не действие, а состояние.
    func dipleSelected<S: InsettableShape>(_ isSelected: Bool, in shape: S) -> some View {
        self
            .background(isSelected ? DipleColor.accentSoft : DipleColor.surfaceOverlay, in: shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? DipleColor.accent : Color.clear,
                    lineWidth: DipleStroke.regular * 1.5
                )
            }
    }
}
```

**Перевести на него:**

| Файл | Сейчас | Станет |
|---|---|---|
| `LibraryView.filterBar` | заливка акцентом | `.dipleSelected(_, in: Capsule())`, текст `accentInk` |
| `NotesView.filterChip` | заливка акцентом | то же |
| `GlobalSearchView.scopeChip` | заливка акцентом | то же |
| `ReaderSettingsView.fontFamilyButton` | заливка акцентом | обводка, **и оставить образец на цвете страницы** — см. P8.4 |
| `ReaderSettingsView.readingModeButton` | заливка акцентом | `.dipleSelected` |
| `AppSettingsView` appearance / haptic intensity | заливка акцентом | `.dipleSelected` |
| `AppSettingsView` accent swatch | кольцо + галочка | **оставить как есть** — это выбор самого акцента, залить его нечем |
| `DipleTabBar` | капсула `accentSoft` | **оставить** — это и есть `accentSoft`-регистр |

**Заодно чинится баг:** `NoteCardView.swift:22` и `AppSettingsView.swift:133` возвращают
литерал `.black` вместо `DipleColor.textOnAccent` — цвет вне рампы, нарушение правила,
записанного в заголовке `DipleColor.swift`. После перехода на `.dipleSelected` оба исчезают.

---

### P8. Читалка

**8.1. Дублирование названия.** Сейчас заголовок книги стоит в верхнем баре и он же —
усечённой строкой в нижнем (скриншот: `Artificial Rosetta Sto…` сверху и
`Artificial Rosetta Stone:Con…` снизу). Одна и та же строка дважды на одном экране.

Решение: **верхний бар — только chevron и инструменты**. Ориентирует нижний:
`4 % · 58 min left · <глава>`. Если у локатора нет `title`, нижний бар печатает название
книги — то есть строка всегда есть, но всегда одна. Верхний бар при этом получает воздух,
и кластер из четырёх иконок перестаёт душить.

**8.2. Процент — не акцентом.** `ReaderContainerView`, строка с `percentage`:
`DipleColor.accent` → `chrome.control`. Число — это факт, а не действие; акцент в читалке
уже занят линейкой прогресса, а на светлой странице латунь на бумаге ещё и нечитаема (P1).

**8.3. Переносы.** `ReaderSettings.epubPreferences` ставит `prefs.hyphens = true` — решение
обосновано (русские и немецкие композиты на узкой полосе). Но на английском при текущей мере
получается **5 переносов на экран** (замерено на скриншоте: `explic-itly`, `tradi-tions`,
`re-search`, `ele-ment`, `recon-struction`, `machine-`, `with-out`). Matter не переносит вовсе.

Не выключать — ограничить. Добавить в стилевой слой страницы:

```css
-webkit-hyphenate-limit-before: 4;
-webkit-hyphenate-limit-after: 3;
-webkit-hyphenate-limit-lines: 2;
```
Это убивает `re-search` и `with-out`, оставляя `recon-struction` и русские композиты.

> ⚠️ **Проверить по исходникам Readium перед реализацией** (правило №1 в `CLAUDE.md`).
> Кандидаты: `readiumCSSRSProperties` (читается один раз при создании навигатора — см.
> «Шрифт читалки» в `CLAUDE.md`) либо инъекция пользовательского стиля рядом с тем, как это
> уже сделано в `ReaderFontDeclarations`. Не угадывать API.

**8.4. Панель настроек читалки — образцы, а не заливка.**

Свотчи тем — лучший контрол в приложении именно потому, что каждый нарисован своей бумагой.
Кнопки гарнитур ровно это ломают: выбранная «New York» залита латунью и набрана тёмным — то
есть образец показывает то, чего на странице никогда не будет.

Привести к одному виду со свотчами тем:
- фон кнопки = `theme.swatchBackground` текущей темы страницы;
- текст = `theme.swatchInk`, набран самой гарнитурой (уже так, `fontOptionLabel`);
- выбор = обводка акцентом 2 pt (как у `themeButton`).

Тогда обе сетки на листе читаются одной системой, и обе честно показывают результат.

**8.5. Головное поле страницы.** Первая строка стоит вплотную к безопасной зоне. У книги
головное поле меньше хвостового, но оно есть. Добавить небольшой верхний инсет к
`navigatorContentInset` (порядка `DipleSpace.m`), чтобы текст не начинался от самой кромки.

---

### P9. Светлая тема: сделать её бумагой

**Проблема (Д3).** `canvas` в светлой — `#F4F4F7`, холодный серый. Комментарий в
`DipleColor` объясняет холодный подтон как приём для тёмной темы («холодный подтон — то, что
делает тёмный интерфейс глубоким, а не мутным») и распространяет его на светлую, где он даёт
обратный эффект: бумага издательства тёплая, а не синеватая.

**Решение.** Развести подтоны по темам.

```swift
/// Тёплая, а не холодная. Холодный подтон делает тёмный интерфейс глубоким; на светлом он
/// делает бумагу больничной. Издательская бумага всегда сдвинута в жёлтый.
public static let canvas = adaptive(
    light: UIColor(red: 0.969, green: 0.961, blue: 0.945, alpha: 1),   // #F7F5F1
    dark:  UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)    // без изменений
)

public static let surfaceOverlay = adaptive(
    light: UIColor(red: 0.929, green: 0.918, blue: 0.898, alpha: 1),   // #EDEAE5
    dark:  UIColor(red: 0.137, green: 0.137, blue: 0.173, alpha: 1)
)
```
`surface` / `surfaceRaised` остаются чисто белыми — тогда карточка на тёплом холсте читается
как лист, положенный на стол, а строки каталога, лежащие прямо на холсте, читаются как
напечатанные на самой бумаге. Это ровно та модель, которую заголовок `DipleColor` уже
описывает словами, но не выполняет числами.

**Проверить заодно:** `UIColor.dipleCanvas` в том же файле дублирует литерал для UIKit-слоёв
читалки — обновить обе точки, иначе шов на границе навигатора.

---

### P10. Издательский стиль текста (house style)

У издательства есть свод правил набора. У diple его нет — и это видно.

**10.1. Регистр заголовков.** Сейчас смешаны Title Case и sentence case:

| Title Case | sentence case |
|---|---|
| `Library is Empty`, `No Quotes Yet`, `Nothing Found`, `No Table of Contents`, `No Bookmarks Saved`, `Search Everything`, `New Note`, `Import a Book`, `Delete Book?`, `Enable Haptics`, `Daily Quote`, `Privacy Policy` | `Start with something real`, `Inbox is clear`, `Write the first note`, `Nothing in this view`, `No matching notes` |

**Правило:** sentence case везде. Прописные — только у вордмарка и у рубрик (`.micro`/`.nano`
uppercase). Title Case — американская газетная манера, она спорит с минимализмом.

**10.2. Одно имя для одной вещи.** Сейчас сохранённый пассаж называется тремя словами:

- `HubView.navigationTitle` = **Highlights**
- `HubView.emptyState` = **No Quotes Yet**
- `HomeView` = **saved passages**
- `LibraryView` алерт = *«Its quotes will remain in Quotes»*
- `BookOutlineSheetView` сегмент = **Quotes**

**Правило:** коллекция — **Highlights**; отдельный элемент в прозе — **passage**. Слово
*quote* вычищается из интерфейса целиком (в коде `Highlight`/`quoteCount` остаются — это
модель, её переименование трогает данные и требует отдельного разговора).

**10.3. Многоточие.** `Importing book...` (`LibraryView:155`) и `Loading book...`
(`ReaderContainerView:83`) набраны тремя точками; остальное приложение использует `…`.
Заменить. Заодно: `Importing book…` → `Adding to your library…`, чтобы совпасть с
формулировкой в `HomeView.importingOverlay` — это один и тот же процесс, названный дважды.

---

### P11. Мелкие долги (одним коммитом)

| Файл | Что |
|---|---|
| `ImportLinkSheetView:157,170`, `AppSettingsView:624` | `.easeInOut`/`.easeOut` → `DipleMotion.standard`. Последние три нарушения шага 4 плана. `LivingMarginView:95` и `ReaderContainerView:657` — **не трогать**, там это ветка `reduceMotion`, и она правильная. |
| `ReaderContainerView` (ветка ошибки) | `.background(...)` + `.cornerRadius(...)` → `.craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.s)`. `cornerRadius` устарел и не даёт непрерывного скругления. |
| `NoteCardView:22`, `AppSettingsView:133` | `.black` → `DipleColor.textOnAccent` (снимается само в P7). |
| `NoteCardView` | Сравнение `title == "Untitled"` — строковая проверка вместо флага; сломается при локализации. Ввести `NoteItem.isUntitled`. |
| `LibraryView` алерт удаления | Формулировка на две строки с оправданиями. Сократить: «Удаляется файл и позиция чтения. Сохранённые пассажи останутся в Highlights.» |

---

## 3. Порядок внедрения

Каждый пункт — отдельный агент, отдельный коммит, `push` в `main` (по договорённости из
памяти проекта). Порядок обязателен: поздние пункты опираются на токены ранних.

| # | Правка | Зависит от | Риск |
|---|---|---|---|
| 1 | **P1** акцент как чернила | — | низкий, чистая замена токена |
| 2 | **P9** тёплый светлый холст | — | низкий, две константы |
| 3 | **P7** единый язык выбора | P1 | средний, ~10 файлов |
| 4 | **P10** house style текста | — | низкий, только строки |
| 5 | **P11** мелкие долги | P7 | низкий |
| 6 | **P3** вторая гарнитура | — | средний: новый ресурс + `Info.plist` |
| 7 | **P2** `DipleMasthead` | P3 | **высокий**: трогает три корня и навигацию |
| 8 | **P4** Library: хром | P2, P7 | **высокий**: `List` + `swipeActions` |
| 9 | **P5** Notes: плита | P2 | средний |
| 10 | **P6** Home + низ страницы | P2 | средний |
| 11 | **P8** читалка | P1, P7 | средний; п. 8.3 требует проверки API Readium |

**Каждому агенту передавать:**
```
xcodebuild -project diple.xcodeproj -scheme diple \
  -destination 'generic/platform=iOS Simulator' build
```
и явный список путей для `git add` — `git add -A` подметёт чужие файлы (записано в памяти).
Диагностика SourceKit в этом репозитории лжёт («No such module 'UIKit'»); считается только
результат `xcodebuild`.

---

## 4. Что делать НЕ надо

- **Не менять модель данных.** Ни одна правка выше её не касается — и не должна.
  `Highlight.colorHex`, `AppSettings`, схема CloudKit развёрнута в Production и односторонняя.
- **Не трогать шрифт страницы читалки.** Вопрос «настоящий SF через `fontFaces`» открыт с
  2026-08-13 и решается отдельно; вторая гарнитура из P3 — это гарнитура **интерфейса**, в
  веб-вью она не попадает.
- **Не добавлять теней.** `DipleSurface` строит глубину кромкой. Две существующие тени
  (бар читалки, таб-бар) оправданы — они лежат на непредсказуемом фоне. Третьей быть не должно.
- **Не вводить третий цвет.** Акцент + `destructive` + `success` — весь цветовой словарь.
- **Не делать анимаций входа списков.** Стаггер в `GlobalSearchView` — исключение с
  обоснованием (пять групп в одном кадре читаются как вспышка). Копировать его на полку и
  доску не нужно: там одна группа.
- **Не возвращать iPad.** `TARGETED_DEVICE_FAMILY = 1` — решение принято после аудита
  13-дюймового симулятора. Все правки выше — компактная ширина.
