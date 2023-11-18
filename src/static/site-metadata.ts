interface ISiteMetadataResult {
  siteTitle: string;
  siteUrl: string;
  description: string;
  logo: string;
  navLinks: {
    name: string;
    url: string;
  }[];
}

const data: ISiteMetadataResult = {
  siteTitle: 'Li Peng\'s Running Page',
  siteUrl: 'https://lipeng-run.vercel.app',
  logo: 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQTtc69JxHNcmN1ETpMUX4dozAgAN6iPjWalQ&usqp=CAU',
  description: 'My running statistics. Thanks to [Yi Hong](https://github.com/yihong0618) for developing this amazing project.',
  navLinks: [
    {
      name: 'Blog',
      url: 'https://www.strava.com/athletes/126825325',
    },
    {
      name: 'About',
      url: 'https://www.strava.com/athletes/126825325',
    },
  ],
};

export default data;
