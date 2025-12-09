#ifndef GAMEBACKEND_H
#define GAMEBACKEND_H

#include <QObject>
#include <QVector>
#include <QVariant>
#include <QString>
#include <QDebug>
#include <string>
#include <vector>
#include <random>
#include <algorithm>
#include <cmath>

using namespace std;

struct Effect {
    string name; //영향 이름
    int impact; //주가에 미치는 영향
    int duration; //남은 지속시간
    bool reversed; //종료 후 반전 플래그
};

struct Company {
    string name; //회사 이름
    double BasePrice; //기본 주가
    double FinalPrice; //계산 후의 최종 주가
    vector<string> features; //회사의 특징
    vector<Effect> effects; //적용중인 영향(이펙트)
    int amount; //보유중인 주식 수
    vector<double> history; //주가 변동 기록
    string description; //회사 정보 설명
};

struct Event {
    string name; //이벤트 이름
    bool single; //이벤트 대상이 하나인지 체크
    bool stackable; //이벤트 효과가 같은 회사에 중첩 가능한지 체크
    int impact; //주가에 미치는 영향
    vector<string> target; //이벤트 영향을 받는 회사의 특징
    vector<Effect> effect; //어떤 버프/디버프를 부여하는지
    int cooltime; //이벤트 쿨타임(일수)
    int current_cooltime; //남은 쿨타임(일수)
    string sentence; //뉴스 내용
    int chance; //이벤트 발생 확률
};

class GameBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(int day READ day NOTIFY dataChanged)
    Q_PROPERTY(double cash READ cash NOTIFY dataChanged)
    Q_PROPERTY(double totalAsset READ totalAsset NOTIFY dataChanged)
    Q_PROPERTY(double prevAsset READ prevAsset NOTIFY dataChanged)
    Q_PROPERTY(QString newsTitle READ newsTitle NOTIFY newsChanged)
    Q_PROPERTY(QString newsBody READ newsBody NOTIFY newsChanged)
    Q_PROPERTY(QVariantList stockList READ stockList NOTIFY dataChanged)
    Q_PROPERTY(double goalAmount READ goalAmount CONSTANT)
    Q_PROPERTY(int maxDay READ maxDay CONSTANT)

public:
    explicit GameBackend(QObject *parent = nullptr) : QObject(parent) {
        initData();
        calculateTotalAsset();
    }

    int day() const { return m_day; }
    double cash() const { return m_cash; }
    double totalAsset() const { return m_totalAsset; }
    double prevAsset() const { return m_prevAsset; }
    QString newsTitle() const { return m_newsTitle; }
    QString newsBody() const { return m_newsBody; }
    double goalAmount() const { return goal; }
    int maxDay() const { return last_day; }

    QVariantList stockList() const {
        QVariantList list;
        for(const auto& c : companyList) {
            QVariantMap map;
            map["name"] = QString::fromStdString(c.name);
            map["price"] = c.FinalPrice;
            map["owned"] = c.amount;
            map["description"] = QString::fromStdString(c.description);

            double changeRate = 0.0;
            if(c.history.size() >= 2) {
                double yesterday = c.history[c.history.size() - 2];
                if(yesterday != 0)
                    changeRate = ((c.FinalPrice - yesterday) / yesterday) * 100.0;
            }
            map["changeRate"] = changeRate;
            list.append(map);
        }
        return list;
    }

    Q_INVOKABLE QVariantList getStockHistory(int index) {
        QVariantList list;
        if(index >= 0 && index < companyList.size()) {
            for(double price : companyList[index].history) {
                list.append(price);
            }
        }
        return list;
    }

    Q_INVOKABLE void buyStock(int index, int amount) {
        if(index < 0 || index >= companyList.size() || amount <= 0) return;
        Company& c = companyList[index];
        double cost = c.FinalPrice * amount;
        if(m_cash >= cost) {
            m_cash -= cost;
            c.amount += amount;
            calculateTotalAsset();
            emit dataChanged();
        }
    }

    Q_INVOKABLE void sellStock(int index, int amount) {
        if(index < 0 || index >= companyList.size() || amount <= 0) return;
        Company& c = companyList[index];
        if(c.amount >= amount) {
            m_cash += (c.FinalPrice * amount);
            c.amount -= amount;
            calculateTotalAsset();
            emit dataChanged();
        }
    }

    Q_INVOKABLE void nextTurn() {
        if(m_day > last_day) return;
        m_prevAsset = m_totalAsset;

        for(auto& event : eventList) {
            if(event.current_cooltime > 0) event.current_cooltime--;
        }

        UpdateEffects();
        ProcessEvents();

        for (auto& company : companyList) {
            CalculatePrice(company);
        }

        m_day++;
        calculateTotalAsset();
        emit dataChanged();
        emit newsChanged();

        if(m_day > last_day) {
            bool isVictory = (m_totalAsset >= goal);
            QString message;
            if (isVictory) {
                message = QString("축하합니다!\n목표 자산 %1원을 달성했습니다.\n최종 자산: %2원")
                              .arg((long long)goal).arg((long long)m_totalAsset);
            } else {
                message = QString("게임 오버...\n목표 자산 달성에 실패했습니다.\n부족한 금액: %1원")
                              .arg((long long)(goal - m_totalAsset));
            }
            emit gameOver(isVictory, message);
        }
    }

private:
    int m_day = 1;
    double m_cash = 1200000;
    double m_totalAsset = 1200000;
    double m_prevAsset = 1200000;
    double goal = 4000000;
    int last_day = 30;
    QString m_newsTitle = "시장 개장";
    QString m_newsBody = "본격적인 거래가 시작되었습니다.";

    vector<Company> companyList;
    vector<Effect> effectList;
    vector<Event> eventList;
    vector<string> newsList;

    int random_num(int min, int max) {
        static std::random_device rd;
        static std::mt19937 gen(rd());
        if (min > max) std::swap(min, max);
        std::uniform_int_distribution<> dis(min, max);
        return dis(gen);
    }

    bool roll(int chance) { return random_num(1, 100) <= chance; }

    Effect* CheckEffect(Company& company, const string& effectName) {
        for (auto& e : company.effects) { if (e.name == effectName) return &e; }
        return nullptr;
    }

    void AddEffect(Company& company, const string& effectName) {
        Effect* baseEffect = nullptr;
        for (auto& eff : effectList) { if (eff.name == effectName) { baseEffect = &eff; break; } }
        if (!baseEffect) return;
        for (auto& eff : company.effects) {
            if (eff.name == effectName) { eff.duration = baseEffect->duration; return; }
        }
        company.effects.push_back(*baseEffect);
    }

    void UpdateEffects() {
        for (auto& company : companyList) {
            for (int i = company.effects.size() - 1; i >= 0; i--) {

                company.effects[i].duration--;

                // 지속시간이 끝난 경우
                if (company.effects[i].duration <= 0) {

                    // 아직 반전되지 않은 효과라면 → 반전 처리
                    if (!company.effects[i].reversed) {

                        // impact 반전
                        company.effects[i].impact = -company.effects[i].impact;
                        company.effects[i].reversed = true;

                        // 초기 지속시간 가져오기
                        int originalDuration = 0;
                        for (auto& base : effectList) {
                            if (base.name == company.effects[i].name) {
                                originalDuration = base.duration;
                                break;
                            }
                        }

                        // 재적용
                        company.effects[i].duration = originalDuration;
                    }
                    else {
                        // 이미 반전된 효과인데 지속시간까지 끝났다면 → 최종 삭제
                        company.effects.erase(company.effects.begin() + i);
                    }
                }
            }
        }
    }


    double CalculatePrice(Company& company) {
        double value = 0;
        //현재 기업이 가진 모든 버프/디버프 영향력 합산
        for (const auto& effect : company.effects) value += effect.impact;

        //소폭 변동(기준가에 적용)
        double minorChange = roll(50) ? 1.02 : 0.98;
        company.BasePrice *= minorChange;

        //이벤트 영향 적용(기준가 적용)
        double buffChangePercent = 0.0;
        if (value > 0) {
            if (roll(90)) buffChangePercent = random_num(0, value) / 100.0;
            else buffChangePercent = -(random_num(0, value/2) / 100.0);
        } else if (value < 0) {
            int v = abs(value);
            if (roll(90)) buffChangePercent = -(random_num(0, v) / 100.0);
            else buffChangePercent = (random_num(0, v/2) / 100.0);
        }

        company.BasePrice *= (1.0 + buffChangePercent);
        //노이즈(최종가 적용,95%~105%)
        double noise = random_num(95, 105) / 100.0;
        double result = company.BasePrice * noise;

        company.FinalPrice = result;
        company.history.push_back(result);
        return result;
    }

    void ProcessEvents() {
        vector<string> finalNews;
        //발생 여부 판정(모든 이벤트 순회)
        for (auto& event : eventList) {
            //이벤트 쿨타임 체크
            if(event.current_cooltime > 0) continue;
            //이벤트 확률 체크
            if (random_num(1, 100) > event.chance) continue;

            //이벤트 타겟 결정
            vector<Company*> candidates;
            //모든 회사 순회
            for (auto& company : companyList) {
                //이벤트 타겟이 비어있으면(모든 대상) true 아니면 false
                bool matchesTarget = event.target.empty();
                if (!matchesTarget) {
                    //회사 특징 순회
                    for (const auto& feature : company.features) {
                        //이벤트 타겟 목록 안에 회사의 특징이 있는지 검사
                        if (find(event.target.begin(), event.target.end(), feature) != event.target.end()) {
                            //찾았으면 합격
                            matchesTarget = true;
                            break;
                        }
                    }
                }
                //찾지 못했으면 해당 회사 건너뛰기
                if (!matchesTarget) continue;
                //중복 적용 검사(중첩 불가능이면 검사 건너뜀)
                if (!event.stackable) candidates.push_back(&company);
                //중복 검사 시작
                else {
                    bool hasEffect = false;
                    //이벤트 효과 목록 순회
                    for (auto& eff : event.effect) {
                        //해당 효과가 현재 회사에 있는지 체크
                        if (CheckEffect(company, eff.name)){
                            hasEffect = true;
                            break;
                        }
                    }
                    //효과가 없다면 후보로 등록
                    if (!hasEffect) candidates.push_back(&company);
                }
            }

            //후보가 존재하는지 확인
            if (candidates.empty()) continue;
            //쿨타임 시작
            event.current_cooltime = event.cooltime;

            vector<Company*> applyCompanies;
            //단일 대상 이벤트면
            if (event.single) {
                //후보 하나만 랜덤 선택
                int idx = random_num(0, candidates.size() - 1);
                applyCompanies.push_back(candidates[idx]);
            //전체 대상 이벤트면
            } else {
                applyCompanies = candidates;
            }
            //주가 변동 시작
            for (auto* company : applyCompanies) {
                //기준가 변경
                company->BasePrice *= (1.0 + event.impact / 100.0);
                //영향(이펙트) 적용
                for (auto& eff : event.effect) AddEffect(*company, eff.name);
                //뉴스 텍스트
                string msg = event.sentence;
                size_t pos = msg.find("<company>");
                if (pos != string::npos) msg.replace(pos, 9, company->name);
                //뉴스 중복 방지
                bool exists = false;
                for(const auto& existingMsg : finalNews) { if(existingMsg == msg) { exists = true; break; } }
                if (!exists) finalNews.push_back(msg);
            }
        }
        //일반 뉴스 추가
        if (!newsList.empty()) {
            int newsCount = random_num(2, 3);
            for (int i = 0; i < newsCount; i++) {
                string candidate = newsList[random_num(0, newsList.size() - 1)];
                bool exists = false;
                for(const auto& s : finalNews) if(s == candidate) exists = true;
                if (!exists) finalNews.push_back(candidate);
            }
        }

        m_newsTitle = QString::asprintf("Day %d 일일 브리핑", m_day);
        m_newsBody = "";
        if (finalNews.empty()) m_newsBody = "오늘은 특별한 소식이 없습니다.";
        else {
            std::shuffle(finalNews.begin(), finalNews.end(), std::mt19937(std::random_device{}()));
            for (const auto& news : finalNews) m_newsBody += QString::fromStdString("- " + news + "\n\n");
        }
    }

    void calculateTotalAsset() {
        double stockVal = 0;
        for(const auto& c : companyList) stockVal += (c.FinalPrice * c.amount);
        m_totalAsset = m_cash + stockVal;
    }

    void initData() {
        // [수정] history에 초기값(BasePrice)을 미리 넣어두어 D0 값을 확보합니다.
        companyList = {
            {"에어니온", 98000.0, 98000.0, {"가전제품", "대기업", "제조업", "수출"}, {}, 0, {98000.0},
             "에어니온은 냉장고·세탁기·에어컨을 포함한 다양한 가전제품을 생산하는 글로벌 제조 대기업으로, 내수 시장은 물론 해외 수출에서도 강한 존재감을 보여주고 있습니다."},
            {"홈렉스", 88000.0, 88000.0, {"가전제품", "대기업", "제조업"}, {}, 0, {88000.0},
             "홈렉스는 생활 가전에 특화된 대기업으로, 중저가형 가전 제품군에서 높은 시장 점유율을 보유하고 있으며 탄탄한 제조 기반을 바탕으로 국내 소비자들에게 널리 사랑받고 있습니다."},
            {"스틸포지", 63000.0, 63000.0, {"철강", "대기업", "제조업", "수출"}, {}, 0, {63000.0},
             "스틸포지는 국내 철강 산업을 대표하는 기업으로, 산업용 강판과 특수 강재를 중심으로 제품을 생산하며 해외 조선·건설 업체들과의 꾸준한 계약을 통해 수출 비중이 높습니다."},
            {"그린팜푸드", 24000.0, 24000.0, {"식료품", "중견기업"}, {}, 0, {24000.0},
             "그린팜푸드는 신선식품·가공식품을 주력으로 하는 중견 식품 기업으로, 안전성과 품질 관리에 강점을 지녀 꾸준한 소비층을 확보하고 있습니다."},
            {"오토드라이브", 112000.0, 112000.0, {"자동차", "대기업", "제조업"}, {}, 0, {112000.0},
             "오토드라이브는 세단·SUV·전기차 등 다양한 라인업을 보유한 자동차 제조 대기업으로, 혁신적인 기술과 안정성으로 국내 시장에서 높은 신뢰도를 자랑합니다."},
            {"파워모터스", 96000.0, 96000.0, {"자동차", "대기업", "수출", "제조업"}, {}, 0, {96000.0},
             "파워모터스는 스포츠카와 고성능 차량군에서 강세를 가진 자동차 수출 대기업으로, 해외 모터스포츠 시장에서도 기술력을 인정받으며 글로벌 인지도를 높여가고 있습니다."},
            {"퓨처소프트", 145000.0, 145000.0, {"소프트웨어", "대기업"}, {}, 0, {145000.0},
             "퓨처소프트는 클라우드·AI·보안 솔루션을 중심으로 성장한 IT 대기업으로, 대규모 기업용 소프트웨어 시장에서 선도적인 위치를 차지하고 있습니다."},
            {"넥트론", 36000.0, 36000.0, {"소프트웨어", "중견기업"}, {}, 0, {36000.0},
             "넥트론은 모바일 앱·게임·사내 솔루션 등 다양한 소프트웨어를 개발하는 중견 기업으로, 민첩한 개발력과 신기술 적용으로 꾸준히 성장세를 이어가고 있습니다."}
        };


        effectList = {
            {"해외시장 진출", +4, 12, false}, {"유행", +3, 5, false}, {"신제품 개발 성공", +5, 7, false}, {"신규 공장 완성", +5, 10, false},
            {"정부의 산업 지원 발표", +5, 10, false}, {"대규모 투자 유치", +4, 8, false}, {"신규 기술 특허 획득", +4, 6, false},
            {"경쟁사 제품 문제 발생", +3, 6, false}, {"핵심 파트너십 체결", +3, 7, false}, {"유명 인플루언서 홍보", +2, 4, false},
            {"해외 규제 완화 혜택", +4, 10, false}, {"대형 계약 수주", +5, 8, false}, {"브랜드 이미지 상승", +2, 6, false}, {"시장 점유율 증가", +3, 7, false},

            {"파업", -4, 4, false}, {"인력 이탈", -3, 5, false}, {"주요 자원 수급 불안", -4, 6, false}, {"안정성 문제 제기", -4, 5, false},
            {"정부 규제 강화", -3, 10, false}, {"경쟁사 신제품 출시", -3, 6, false}, {"주요 고객사 계약 종료", -3, 8, false},
            {"안전 문제 발생", -3, 7, false}, {"부정적 여론 확산", -2, 5, false}, {"경영진 교체 불안감", -2, 5, false},
            {"원자재 가격 급등", -3, 8, false}, {"환율 악재", -2, 6, false}, {"해외 규제 리스크", -3, 7, false}
        };


        eventList = {//일부 뉴스문장 수정, 즉시 양수 버프값 약간 증가, 소프트웨어 회사에게 악영향을 줄수있는 이벤트 2개 추가
                     {"해외시장 진출", true, false, +9, {}, {{"해외시장 진출"}}, 3, 0, "<company>, 해외시장 신규 진출 성공… 해외 수요 증가 기대", 20},
                     {"신제품 히트", true, false, +11, {"가전제품","자동차","소프트웨어"}, {{"유행"}}, 3, 0, "<company>, 신제품 판매 급증… 관련 업계 주목", 15},
                     {"정부 지원금 수혜", false, false, +7, {"중견기업"}, {{"정부의 산업 지원 발표"}}, 3, 0, "정부, 중견기업 대상 산업 지원금 발표… 대상 기업 주가 상승 기대", 10},
                     {"주요 계약 체결", true, false, +9, {"제조업","자동차","소프트웨어"}, {{"대형 계약 수주"}}, 3, 0, "<company>, 주요 기업과 대형 계약 체결 성공", 12},
                     {"대규모 해외 계약", true, false, +22, {"대기업","수출"}, {{"대형 계약 수주"}}, 5, 0, "<company>, 해외 대규모 수출 계약 체결… 주가 강세", 5},
                     {"트렌드 급상승", false, false, +6, {"소프트웨어","가전제품","식료품"}, {{"유행"}}, 3, 0, "올해 소비 트렌드 변화로 해당 업종(가전·식품·소프트웨어) 기업 매출 기대감 증가", 8},
                     {"국제 전시회 성공", true, false, +11, {"가전제품","자동차","수출"}, {{"해외시장 진출"}}, 3, 0, "<company>, 국제 전시회에서 해외 구매자 관심 집중", 7},
                     {"글로벌 파트너십 체결", true, false, +13, {"소프트웨어","제조업"}, {{"핵심 파트너십 체결"}}, 3, 0, "<company>, 해외 유력 기업과 전략적 파트너십 체결", 6},
                     {"유명 인플루언서 협업", true, false, +6, {"식료품","가전제품"}, {{"유명 인플루언서 홍보"}}, 3, 0, "<company>, 유명 인플루언서 협업으로 제품 관심도 급증", 9},
                     {"규제 완화 혜택", false, false, +7, {"수출","제조업"}, {{"해외 규제 완화 혜택"}}, 3, 0, "정부, 수출·제조 업계 대상 해외 규제 완화 발표… 관련 기업 수혜 기대", 7},
                     {"브랜드 이미지 개선", true, false, +6, {}, {{"브랜드 이미지 상승"}}, 3, 0, "<company>, 브랜드 이미지 상승… 소비자 선호도 증가", 8},
                     {"시장 점유율 확대", true, false, +7, {"식료품","가전제품","자동차"}, {{"시장 점유율 증가"}}, 3, 0, "<company>, 시장 점유율 확대로 성장세 이어가", 6},
                     {"대규모 투자 유치 성공", true, false, +15, {"대기업","수출","자동차"}, {{"대규모 투자 유치"}}, 5, 0, "<company>, 해외 투자사로부터 대규모 자금 유치 성공", 5},
                     {"신기술 특허 취득", true, false, +15, {"소프트웨어","가전제품","제조업"}, {{"신규 기술 특허 획득"}}, 5, 0, "<company>, 차세대 핵심 기술 특허 취득", 8},
                     {"신규 공장 준공", true, false, +11, {"제조업"}, {{"신규 공장 완성"}}, 5, 0, "<company>, 신규 생산 공장 완공… 생산능력 확대 기대", 7},
                     {"생산 라인 화재", true, true, -18, {"제조업"}, {{"안전 문제 발생"}}, 5, 0, "<company>, 생산 라인 화재로 공정 차질", 5},
                     {"리콜 사태", true, true, -10, {"자동차","가전제품"}, {{"안정성 문제 제기"}}, 5, 0, "<company>, 제품 리콜 사태 발생… 신뢰도 하락", 7},
                     {"해외 수출 규제", false, false, -8, {"수출"}, {{"해외 규제 리스크"}}, 3, 0, "해외 규제 강화로 수출 업계 타격… 관련 기업 우려 증가", 5},
                     {"사이버 보안 사고", true, true, -6, {"소프트웨어"}, {}, 3, 0, "<company>, 보안 사고 발생… 서비스 신뢰성 논란", 8},
                     {"자연재해 피해", true, true, -20, {"제조업","식료품","자동차"}, {}, 5, 0, "<company>, 자연재해로 생산시설 피해 발생", 3},
                     {"경영진 스캔들", true, true, -5, {}, {{"경영진 교체 불안감"}}, 5, 0, "<company>, 경영진 스캔들로 투자자 불안", 5},
                     {"원자재 가격 폭등", false, true, -5, {"제조업","자동차","철강"}, {{"원자재 가격 급등"}}, 3, 0, "원자재 가격 급등으로 제조·철강 업계 비용 부담 증가", 6},
                     {"전국 파업 확산", false, true, -5, {"제조업","철강","자동차"}, {{"파업"}}, 3, 0, "전국 파업 확산으로 제조·철강·자동차 업종 생산 차질 우려", 7},
                     {"핵심 인력 대거 이탈", true, true, -4, {"소프트웨어","제조업"}, {{"인력 이탈"}}, 3, 0, "<company>, 핵심 인력 대거 이탈로 프로젝트 차질 우려", 6},
                     {"자원 공급 불안정", false, true, -5, {"철강","제조업"}, {{"주요 자원 수급 불안"}}, 3, 0, "자원 공급 불안정으로 철강·제조 업계 전반에 공급 차질 우려", 4},
                     {"품질 논란 발생", true, true, -5, {"가전제품","식료품"}, {{"안정성 문제 제기"}}, 3, 0, "<company>, 품질 논란 발생… 소비자 신뢰 하락", 5},
                     {"부정 여론 확산", true, true, -3, {}, {{"부정적 여론 확산"}}, 3, 0, "<company> 관련 부정 여론 확산… 이미지 타격", 9},
                     {"경영진 교체 요구", true, true, -3, {"대기업","중견기업"}, {{"경영진 교체 불안감"}}, 3, 0, "<company>, 경영진 교체 요구 증가… 조직 안정성 우려", 6},
                     {"환율 급변 악재", false, true, -3, {"수출","대기업"}, {{"환율 악재"}}, 3, 0, "환율 급등세 영향으로 수출·대기업 업종 부담 증가", 10},
                     {"경쟁사 신제품 출시", false, true, -4, {"가전제품","자동차","소프트웨어"}, {{"경쟁사 신제품 출시"}}, 3, 0, "경쟁사 혁신 신제품 공개… 해당 업종 경쟁 심화", 6},
                     {"주요 고객사 계약 종료", true, true, -6, {"제조업","자동차","가전제품"}, {{"주요 고객사 계약 종료"}}, 3, 0, "<company>, 주요 고객사와의 계약 종료… 매출 감소 우려", 5},
                     {"서버 장애 발생", true, false, -7, {"소프트웨어"}, {}, 6, 0, "<company>, 장기간 서버 장애로 서비스 불안정… 이용자 불만 확산", 6},
                     {"특허 소송 제기", true, false, -6, {"소프트웨어", "중견기업"}, {}, 7, 0, "<company>, 경쟁사로부터 특허 침해 소송 제기… 리스크 확대", 5},
                     };
        newsList = {
            "서울 도심에서 경미한 교통사고 발생.", "부산 해변에서 지역 축제 성황리 개최.", "강원도 일대 소규모 정전 발생, 10분 만에 복구.",
            "서울 한강변에서 반려견 산책 인구 급증.", "지하철역에서 분실물 접수량 증가.", "도심 카페 신규 메뉴 출시로 화제.",
            "시민단체, 환경정화 캠페인 진행.", "비오는 날씨로 우산 대여 서비스 이용 증가.", "지역 마트에서 장바구니 할인 행사 개최.",
            "공원에서 야외 음악 공연 열려 시민들 발걸음 이어져.", "주말에 주요 고속도로 정체 예상.", "도심 곳곳에서 길고양이 급식소 설치.",
            "서울 시내 버스 노선 일시적으로 변경.", "지역 농산물 직거래 장터 오픈.", "시청 앞 분수대에서 어린이 물놀이 인기.",
            "도서관에 신규 도서 대량 입고.", "시민들, 주말 등산객 증가로 산책로 붐벼.", "도심 공원 벚꽃 개화 시작.",
            "야구 경기에서 극적 역전승이 화제.", "새로운 길거리 먹거리 트럭 등장.", "소규모 아파트 단지에서 정전 소동.",
            "인근 초등학교에서 학예회 개최.", "골목길 벽화 마을 SNS에서 인기 급상승.", "마을 주민센터에서 건강검진 행사 열려.",
            "지역 시장에서 반값 세일 진행.", "도심 카페에서 반려동물 동반 가능해져 인기.", "시민들, 주말 비 예보로 우비 구매 증가.",
            "도심 곳곳에 주차 단속 강화 실시.", "하천 산책로에서 드문 철새 포착돼 화제.", "꽁꽁 얼어붙은 한강위로 고양이가 지나갑니다"
        };
    }

signals:
    void dataChanged();
    void newsChanged();
    void gameOver(bool isVictory, QString message);
};

#endif // GAMEBACKEND_H
